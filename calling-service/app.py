"""Stateless test gateway. Audio stays on the phone; only submitted text is sent."""
import asyncio
import os
import secrets
import time
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, model_validator

from providers.base import ProviderConfig, ProviderError
from providers.clinic_receptionist import ClinicReceptionistProvider
from providers.nova_dear_care import NovaDearCareProvider
from providers.rural_health_ai import RuralHealthAIProvider
from phone import install_phone_routes


class Message(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=4000)


class Conversation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    provider: Literal["clinic-receptionist", "nova-dear-care", "rural-health-ai"]
    messages: list[Message] = Field(min_length=1, max_length=20)
    language: str = Field(default="en", min_length=2, max_length=35, pattern=r"^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$")
    context: str = Field(default="", max_length=6000)

    @model_validator(mode="after")
    def valid_turns(self):
        if self.messages[-1].role != "user":
            raise ValueError("The final turn must be the user's message.")
        if any(not message.content.strip() for message in self.messages):
            raise ValueError("Messages must contain text.")
        if any(message.role != ("user" if index % 2 == 0 else "assistant")
               for index, message in enumerate(self.messages)):
            raise ValueError("Messages must alternate, starting with the user.")
        return self


class BodyLimit:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        body = bytearray()
        while True:
            event = await receive()
            if event["type"] == "http.disconnect":
                return
            body.extend(event.get("body", b""))
            if len(body) > 65536:
                await send({"type": "http.response.start", "status": 413,
                            "headers": [(b"content-type", b"application/json")]})
                await send({"type": "http.response.body", "body": b'{"detail":"Request too large."}'})
                return
            if not event.get("more_body", False):
                break
        delivered = False

        async def replay():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, replay, send)


def create_app(config: ProviderConfig | None = None, token: str | None = None, providers=None):
    @asynccontextmanager
    async def lifespan(application):
        try:
            yield
        finally:
            application.state.phone_service.close()

    application = FastAPI(title="Venture call tests", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    application.add_middleware(BodyLimit)
    secret = token if token is not None else os.environ.get("VENTURE_CALL_SERVICE_TOKEN", "")
    config = config or ProviderConfig.from_env()
    registry = providers if providers is not None else {
        provider.id: provider for provider in (
            ClinicReceptionistProvider(config), NovaDearCareProvider(config), RuralHealthAIProvider(config)
        )
    }
    bearer = HTTPBearer(auto_error=False)
    capacity = asyncio.Semaphore(4)

    @application.exception_handler(RequestValidationError)
    async def invalid_request(request: Request, error: RequestValidationError):
        # Validation responses must not echo private screening text or prompts.
        return JSONResponse(status_code=422, content={"detail": "Invalid calling-service request. Check the provider, language, message order, and input lengths."})

    def authenticate(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if len(secret) < 24 or secret.startswith("replace-"):
            raise HTTPException(503, "Set VENTURE_CALL_SERVICE_TOKEN to a random token of at least 24 characters.")
        if credentials is None or not secrets.compare_digest(credentials.credentials, secret):
            raise HTTPException(401, "The calling-service token is missing or incorrect.")

    phone_service = install_phone_routes(application, registry, authenticate, capacity)
    application.state.phone_service = phone_service

    @application.get("/providers", dependencies=[Depends(authenticate)])
    async def provider_status():
        return {"providers": [{
            "id": provider.id, "name": provider.name, "model": provider.model,
            "kind": getattr(provider, "kind", "cloud model"),
            "configured": provider.configured, "detail": provider.unavailable_reason,
        } for provider in registry.values()], "telephony": {
            "configured": phone_service.configured, "detail": phone_service.unavailable_reason,
        }}

    @application.post("/v1/respond", dependencies=[Depends(authenticate)])
    async def respond(conversation: Conversation):
        provider = registry.get(conversation.provider)
        if provider is None:
            raise HTTPException(404, "This experiment has been removed from the service.")
        if not provider.configured:
            raise HTTPException(503, provider.unavailable_reason)
        if capacity.locked():
            raise HTTPException(429, "All calling-service test slots are busy. Try again shortly.")
        started = time.monotonic()
        try:
            async with capacity:
                result = await asyncio.wait_for(provider.complete(
                    [message.model_dump() for message in conversation.messages],
                    conversation.language, conversation.context,
                ), timeout=60)
            if not isinstance(result, str) or not result.strip():
                raise ProviderError("The experiment returned no usable response.")
            return {"provider": provider.id, "text": result.strip(),
                    "latency_ms": round((time.monotonic() - started) * 1000),
                    "model": provider.model, "kind": getattr(provider, "kind", "cloud model")}
        except ProviderError as error:
            raise HTTPException(error.status_code, str(error)) from None
        except TimeoutError:
            raise HTTPException(504, "The experiment timed out. Try a shorter request.") from None
        except Exception:
            # SDK exceptions can contain payloads or credentials. Never return/log them.
            raise HTTPException(502, "The experiment failed to respond.") from None

    return application


app = create_app()
