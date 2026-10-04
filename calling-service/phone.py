"""Optional outbound phone conversations; no recording or transcript persistence."""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import Literal
from urllib.parse import parse_qs, urlencode, urlsplit

import httpx
from fastapi import Depends, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field, StrictBool, model_validator

from providers.base import ProviderError

E164 = r"^\+[1-9][0-9]{7,14}$"
CALL_SID = re.compile(r"^CA[0-9a-fA-F]{32}$")
TERMINAL = {"completed", "canceled", "failed", "busy", "no-answer"}
STATUSES = TERMINAL | {"queued", "initiated", "ringing", "in-progress"}
PROGRESS = {"queued": 0, "initiated": 1, "ringing": 2, "in-progress": 3}
TTL = 900
CONTROL_TTL = 1800  # Minimal call/idempotency metadata outlives personal context.
MAX_SESSIONS = 64
MAX_TURNS = 20
_STOP = re.compile(
    r"^(?:please )?(?:stop(?: calling(?: me)?)?|end (?:this|the) call|hang up|"
    r"goodbye|bye|no thanks|i (?:do not|don't) consent)(?: please)?[.!? ]*$", re.I,
)


@dataclass(frozen=True)
class TwilioConfig:
    account_sid: str = ""
    auth_token: str = ""
    from_number: str = ""
    public_base_url: str = ""

    @classmethod
    def from_env(cls):
        return cls(*(os.environ.get(name, "").strip() for name in (
            "TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM_NUMBER", "TWILIO_PUBLIC_BASE_URL",
        )))

    @property
    def unavailable_reason(self) -> str:
        if not re.fullmatch(r"AC[0-9a-fA-F]{32}", self.account_sid) or len(self.auth_token) < 16:
            return "Set the server's TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN."
        if not re.fullmatch(E164, self.from_number):
            return "Set TWILIO_FROM_NUMBER to your Twilio voice number in international E.164 format."
        try:
            url = urlsplit(self.public_base_url)
            valid = (url.scheme == "https" and url.hostname and not url.username and not url.password
                     and not url.query and not url.fragment and url.port is None
                     and url.hostname.lower() != "localhost" and "_" not in url.hostname
                     and not any(part in {".", ".."} for part in url.path.split("/")))
            if valid:
                try:
                    valid = ipaddress.ip_address(url.hostname).is_global
                except ValueError:
                    valid = "." in url.hostname
            if not valid:
                raise ValueError()
        except ValueError:
            return "Set TWILIO_PUBLIC_BASE_URL to the public HTTPS webhook origin, optionally with a gateway prefix."
        return ""


class OutboundCall(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    opted_in: StrictBool = False
    provider: Literal["clinic-receptionist", "nova-dear-care", "rural-health-ai"]
    to_number: str = Field(pattern=E164)
    language: Literal["en"] = "en"
    context: str = Field(default="", max_length=6000)
    goal: str = Field(default="help me choose one useful next step from my supplied screening evidence.", min_length=1, max_length=1000)
    request_id: str | None = Field(default=None, min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")

    @model_validator(mode="after")
    def require_consent(self):
        if self.opted_in is not True:
            raise ValueError("An explicit phone-call opt-in is required.")
        if not self.goal.strip():
            raise ValueError("The call goal must contain text.")
        return self


class TwilioRESTError(HTTPException):
    def __init__(self, status_code: int, detail: str, definite_rejection: bool):
        super().__init__(status_code, detail)
        self.definite_rejection = definite_rejection


@dataclass
class Attempt:
    fingerprint: str
    provider: str
    expires_at: float
    status: str = "preparing"
    call_sid: str = ""
    session_id: str = ""
    error: str = ""


@dataclass
class CallSession:
    provider: str
    context: str
    initial_request: str
    messages: list[dict[str, str]]
    opening: str
    request_key: str
    expires_at: float
    call_sid: str = ""
    expected_turn: int = 0
    silence_count: int = 0
    responses: dict[int, tuple[str, str]] = field(default_factory=dict)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


def signature(auth_token: str, url: str, form: dict[str, list[str]]) -> str:
    # Include every received field and untrimmed value. Multi-value ordering
    # matches Twilio's public RequestValidator algorithm.
    signed = url + "".join(key + value for key in sorted(form) for value in sorted(set(form[key])))
    digest = hmac.new(auth_token.encode(), signed.encode(), hashlib.sha1).digest()
    return base64.b64encode(digest).decode("ascii")


def spoken(value: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]", " ", value)).strip()[:1600]


def twiml(text: str, action: str = "") -> Response:
    root = ET.Element("Response")
    parent = root
    if action:
        parent = ET.SubElement(root, "Gather", {
            "input": "speech", "action": action, "method": "POST", "language": "en-US",
            "timeout": "8", "speechTimeout": "auto", "actionOnEmptyResult": "true",
        })
    if text:
        ET.SubElement(parent, "Say", {"language": "en-US"}).text = spoken(text)
    if not action:
        ET.SubElement(root, "Hangup")
    return Response(ET.tostring(root, encoding="unicode"), media_type="application/xml",
                    headers={"Cache-Control": "no-store"})


class PhoneService:
    def __init__(self, registry, capacity, config: TwilioConfig, transport=None):
        self.registry = registry
        self.capacity = capacity
        self.config = config
        self.transport = transport
        self.sessions: dict[str, CallSession] = {}
        self.attempts: dict[str, Attempt] = {}
        self.calls: dict[str, str] = {}  # CallSid -> request key; no caller details.
        self._fingerprint_key = secrets.token_bytes(32)
        self._timers: dict[str, asyncio.TimerHandle] = {}
        self._session_timers: dict[str, asyncio.TimerHandle] = {}

    @property
    def configured(self):
        return not self.unavailable_reason

    @property
    def unavailable_reason(self):
        return self.config.unavailable_reason

    def public_url(self, path: str, query: str = "") -> str:
        return self.config.public_base_url.rstrip("/") + path + ("?" + query if query else "")

    def forget_session(self, session_id: str):
        session = self.sessions.pop(session_id, None)
        timer = self._session_timers.pop(session_id, None)
        if timer:
            timer.cancel()
        if session:
            session.context = ""
            session.initial_request = ""
            session.opening = ""
            session.messages.clear()
            session.responses.clear()

    def expire(self, key: str):
        attempt = self.attempts.pop(key, None)
        if attempt:
            self.forget_session(attempt.session_id)
            self.calls.pop(attempt.call_sid, None)
        handle = self._timers.pop(key, None)
        if handle:
            handle.cancel()

    def purge(self):
        now = time.monotonic()
        for key, attempt in list(self.attempts.items()):
            if attempt.expires_at <= now:
                self.expire(key)
        for session_id, session in list(self.sessions.items()):
            if session.expires_at <= now:
                self.forget_session(session_id)

    def close(self):
        for key in list(self.attempts):
            self.expire(key)

    def metadata(self, attempt: Attempt):
        return {"provider": attempt.provider, "call_sid": attempt.call_sid, "status": attempt.status}

    async def rest(self, method: str, call_sid: str = "", data=None):
        suffix = f"/{call_sid}" if call_sid else ""
        url = f"https://api.twilio.com/2010-04-01/Accounts/{self.config.account_sid}/Calls{suffix}.json"
        async with httpx.AsyncClient(timeout=15, follow_redirects=False, transport=self.transport,
                                     auth=(self.config.account_sid, self.config.auth_token)) as client:
            response = await client.request(method, url, data=data)
        if response.status_code >= 300:
            raise TwilioRESTError(503 if response.status_code in {401, 403} else 502,
                                 "Twilio could not confirm the call operation. Check server credentials, number access, and account permissions.",
                                 definite_rejection=400 <= response.status_code < 500)
        value = response.json()
        if not isinstance(value, dict) or not CALL_SID.fullmatch(value.get("sid", "")):
            raise ValueError("Invalid call resource")
        if value.get("status") not in STATUSES:
            raise ValueError("Invalid call status")
        if call_sid and value["sid"] != call_sid:
            raise ValueError("Mismatched call resource")
        return value

    async def provider_response(self, provider_id, messages, context, timeout):
        if self.capacity.locked():
            raise HTTPException(429, "The calling-service assistants are busy. Try again shortly.")
        provider = self.registry.get(provider_id)
        if provider is None:
            raise HTTPException(404, "This experiment has been removed from the service.")
        if not provider.configured:
            raise HTTPException(503, provider.unavailable_reason)
        try:
            async with self.capacity:
                result = await asyncio.wait_for(provider.complete(messages, "en", context), timeout)
            if not isinstance(result, str) or not result.strip():
                raise ProviderError("The assistant returned no usable response.")
            return spoken(result)
        except ProviderError as error:
            raise HTTPException(error.status_code, str(error)) from None
        except TimeoutError:
            raise HTTPException(504, "The assistant timed out.") from None
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(502, "The assistant could not respond.") from None

    async def create(self, call: OutboundCall, idempotency_key: str = ""):
        self.purge()
        payload = call.model_dump(exclude={"request_id"})
        fingerprint = hmac.new(self._fingerprint_key, json.dumps(payload, sort_keys=True).encode(), hashlib.sha256).hexdigest()
        if idempotency_key and not re.fullmatch(r"[a-zA-Z0-9_-]{1,80}", idempotency_key):
            raise HTTPException(422, "Idempotency-Key must contain 1–80 letters, digits, underscores, or hyphens.")
        if call.request_id and idempotency_key and call.request_id != idempotency_key:
            raise HTTPException(409, "The body request_id and Idempotency-Key must match.")
        key = call.request_id or idempotency_key or fingerprint
        previous = self.attempts.get(key)
        if previous:
            if not hmac.compare_digest(previous.fingerprint, fingerprint):
                raise HTTPException(409, "This request id was already used for different call details.")
            if previous.call_sid:
                return self.metadata(previous)
            raise HTTPException(409, previous.error or "This call attempt is still preparing. Reuse this request id; do not create a duplicate call.")
        if len(self.attempts) >= MAX_SESSIONS:
            raise HTTPException(429, "The phone-call session limit is reached. Try again later.")
        attempt = Attempt(fingerprint, call.provider, time.monotonic() + CONTROL_TTL)
        self.attempts[key] = attempt
        self._timers[key] = asyncio.get_running_loop().call_later(CONTROL_TTL, self.expire, key)
        if not self.configured:
            attempt.status = "failed"
            attempt.error = "Phone calling is not configured; no call was placed."
            raise HTTPException(503, self.unavailable_reason)
        # The actual goal remains the caller's turn. All providers receive the
        # same actual supplied evidence, without a generic screening questionnaire.
        messages = [{"role": "user", "content": (
            "[venture outbound call]\nrequested goal: " + spoken(call.goal.strip()) + "\n"
            "Generate the opening message for an opted-in care-coordination call. "
            "You are speaking to clinic staff on behalf of the opted-in app user. "
            "The supplied screening measurements belong to the app user, not the recipient. "
            "Use only the supplied screening evidence and the requested goal; ask one relevant next-step question. "
            "Do not diagnose, invent measurements, confirm availability, or claim a booking. "
            "The user will confirm personal details and appointment choices directly."
        )}]
        try:
            opening = await self.provider_response(call.provider, messages, call.context, 60)
        except HTTPException as error:
            attempt.status = "failed"
            attempt.error = "The assistant opening failed; no call was placed. Start a new intentional request to try again."
            raise HTTPException(error.status_code, attempt.error) from None
        session_id = secrets.token_urlsafe(32)
        attempt.session_id = session_id
        attempt.status = "dialing"
        session = CallSession(call.provider, call.context, messages[0]["content"], [],
                              opening, key, time.monotonic() + TTL)
        self.sessions[session_id] = session
        self._session_timers[session_id] = asyncio.get_running_loop().call_later(TTL, self.forget_session, session_id)
        try:
            resource = await self.rest("POST", data={
                "To": call.to_number, "From": self.config.from_number,
                "Url": self.public_url(f"/twilio/voice/{session_id}"), "Method": "POST",
                "StatusCallback": self.public_url(f"/twilio/status/{session_id}"),
                "StatusCallbackMethod": "POST",
                "StatusCallbackEvent": ["initiated", "ringing", "answered", "completed"],
                "Timeout": "30", "TimeLimit": str(TTL),
            })
        except TwilioRESTError as error:
            if attempt.call_sid:
                # A signed callback proves acceptance even if the REST result
                # is lost or inconsistent. Never overwrite that known outcome.
                return self.metadata(attempt)
            if error.definite_rejection:
                attempt.status = "failed"
                attempt.error = "Twilio rejected this call; no call was placed. Check the server settings before a new intentional attempt."
                self.forget_session(session_id)
            else:
                attempt.status = "unknown"
                attempt.error = "The dial outcome is unknown. Reuse this request id to check; do not create a new request or duplicate call."
            raise HTTPException(error.status_code, attempt.error) from None
        except Exception:
            if attempt.call_sid:
                return self.metadata(attempt)
            # A timed-out POST may already have placed a call. Never retry it.
            attempt.status = "unknown"
            attempt.error = "The dial outcome is unknown. Reuse this request id to check; do not create a new request or duplicate call."
            raise HTTPException(502, attempt.error) from None
        self.bind(session, resource["sid"])
        self.update_status(attempt, resource["status"])
        if attempt.status in TERMINAL:
            self.forget_session(session_id)
        return self.metadata(attempt)

    def bind(self, session: CallSession, call_sid: str):
        if not CALL_SID.fullmatch(call_sid) or (session.call_sid and session.call_sid != call_sid):
            raise HTTPException(403, "The call identifier does not match this session.")
        attempt = self.attempts.get(session.request_key)
        if attempt is None:
            raise HTTPException(410, "The call session expired.")
        session.call_sid = call_sid
        attempt.call_sid = call_sid
        self.calls[call_sid] = session.request_key

    def update_status(self, attempt: Attempt, status: str):
        if attempt.status in TERMINAL:
            return
        if status in TERMINAL or PROGRESS.get(status, -1) >= PROGRESS.get(attempt.status, -1):
            attempt.status = status

    def attempt_status(self, request_id: str):
        self.purge()
        attempt = self.attempts.get(request_id)
        if attempt is None:
            raise HTTPException(404, "This call attempt is unknown or expired.")
        return self.metadata(attempt)

    async def verify(self, request: Request, route_path: str):
        if not self.configured:
            raise HTTPException(503, "Phone webhooks are not configured.")
        if request.headers.get("content-type", "").split(";", 1)[0].strip() != "application/x-www-form-urlencoded":
            raise HTTPException(415, "Twilio webhooks must use form encoding.")
        body = await request.body()
        if len(body) > 65536:
            raise HTTPException(413, "Webhook too large.")
        try:
            form = parse_qs(body.decode("utf-8"), keep_blank_values=True, max_num_fields=100, errors="strict")
            query = request.scope.get("query_string", b"").decode("ascii")
        except (UnicodeError, ValueError):
            raise HTTPException(400, "Invalid webhook form.") from None
        # The route-relative path is the path issued to Twilio. request.url.path
        # can include an ASGI root_path and would duplicate a gateway prefix.
        expected = signature(self.config.auth_token, self.public_url(route_path, query), form)
        supplied = request.headers.get("x-twilio-signature", "")
        if not supplied.isascii() or not hmac.compare_digest(expected, supplied):
            raise HTTPException(403, "Invalid Twilio signature.")
        for key in ("AccountSid", "CallSid", "CallStatus", "SpeechResult"):
            if key in form and len(form[key]) != 1:
                raise HTTPException(400, "Ambiguous webhook fields.")
        if form.get("AccountSid") != [self.config.account_sid] or not CALL_SID.fullmatch(form.get("CallSid", [""])[0]):
            raise HTTPException(403, "The Twilio account or call identifier does not match.")
        self.purge()
        return {key: values[0] for key, values in form.items()}

    async def voice(self, request: Request, session_id: str, turn: int):
        form = await self.verify(request, f"/twilio/voice/{session_id}")
        session = self.sessions.get(session_id)
        if session is None:
            return twiml("this call session has ended. goodbye.")
        self.bind(session, form["CallSid"])
        digest = hashlib.sha256(form.get("SpeechResult", "").encode()).hexdigest()
        async with session.lock:
            # The status callback can clear a session while the provider runs.
            if self.sessions.get(session_id) is not session:
                return twiml("this call session has ended. goodbye.")
            cached = session.responses.get(turn)
            if cached:
                if cached[0] != digest:
                    raise HTTPException(409, "This voice turn was already processed with different input.")
                return Response(cached[1], media_type="application/xml", headers={"Cache-Control": "no-store"})
            if turn != session.expected_turn:
                raise HTTPException(409, "This voice turn is out of sequence.")
            if turn >= MAX_TURNS:
                self.forget_session(session_id)
                return twiml("we have reached the conversation limit. please follow up with your care team. goodbye.")
            speech = spoken(form.get("SpeechResult", ""))
            if turn == 0:
                text = ("hello, this is Venture's automated care assistant, calling with the user's permission. "
                        "you can say stop to end the call. " + session.opening)
            elif _STOP.fullmatch(speech):
                self.forget_session(session_id)
                return twiml("understood. ending this call now. goodbye.")
            elif not speech:
                session.silence_count += 1
                if session.silence_count >= 2:
                    self.forget_session(session_id)
                    return twiml("i did not hear a response. ending this call now. goodbye.")
                text = "i did not hear a response. what would you like to discuss, or would you like to stop?"
            else:
                session.silence_count = 0
                history = [
                    {"role": "user", "content": session.initial_request},
                    {"role": "assistant", "content": session.opening},
                ] + session.messages[-10:] + [{"role": "user", "content": speech}]
                try:
                    text = await self.provider_response(session.provider, history, session.context, 10)
                except HTTPException:
                    self.forget_session(session_id)
                    return twiml("the assistant is unavailable right now. please contact your care team directly. goodbye.")
                if self.sessions.get(session_id) is not session:
                    return twiml("this call session has ended. goodbye.")
                session.messages = (session.messages + [
                    {"role": "user", "content": speech}, {"role": "assistant", "content": text},
                ])[-10:]
            session.expected_turn += 1
            action = self.public_url(f"/twilio/voice/{session_id}", urlencode({"turn": session.expected_turn}))
            response = twiml(text, action)
            session.responses[turn] = (digest, response.body.decode())
            return response

    async def status(self, request: Request, session_id: str):
        form = await self.verify(request, f"/twilio/status/{session_id}")
        session = self.sessions.get(session_id)
        status = form.get("CallStatus", "")
        if status not in STATUSES:
            raise HTTPException(400, "Invalid call status.")
        if session:
            self.bind(session, form["CallSid"])
            attempt = self.attempts[session.request_key]
            # Terminal updates cannot be undone by an older progress callback.
            self.update_status(attempt, status)
            if status in TERMINAL:
                self.forget_session(session_id)
        else:
            # A queued call may not send its first callback until after private
            # context expires. Its signed opaque URL can still recover control
            # metadata without reconstructing any conversation or measurements.
            entry = next(((key, attempt) for key, attempt in self.attempts.items()
                          if attempt.session_id == session_id), None)
            if entry:
                key, attempt = entry
                if attempt.call_sid and attempt.call_sid != form["CallSid"]:
                    raise HTTPException(403, "The call identifier does not match this attempt.")
                attempt.call_sid = form["CallSid"]
                self.calls[attempt.call_sid] = key
                self.update_status(attempt, status)
        return Response(status_code=204)

    async def call_status(self, call_sid: str, cancel=False):
        self.purge()
        key = self.calls.get(call_sid)
        attempt = self.attempts.get(key) if key else None
        if attempt is None:
            raise HTTPException(404, "This call is unknown or its session expired.")
        if attempt.status in TERMINAL:
            return self.metadata(attempt)
        try:
            if cancel:
                # Revocation clears personal state even if the network operation
                # fails. A later voice webhook will return Hangup.
                self.forget_session(attempt.session_id)
                stop_status = "canceled" if attempt.status in {"queued", "initiated", "ringing"} else "completed"
                resource = await self.rest("POST", call_sid, {"Status": stop_status})
            else:
                resource = await self.rest("GET", call_sid)
            self.update_status(attempt, resource["status"])
            if attempt.status in TERMINAL:
                self.forget_session(attempt.session_id)
        except HTTPException:
            if attempt.status in TERMINAL:
                return self.metadata(attempt)
            raise
        except Exception:
            if attempt.status in TERMINAL:
                return self.metadata(attempt)
            raise HTTPException(502, "The call operation could not be confirmed. Keep this call id to check or cancel it again.") from None
        return self.metadata(attempt)


def install_phone_routes(application, registry, authenticate, capacity, *, config=None, transport=None):
    """Install routes with the application's existing bearer-token dependency."""
    service = PhoneService(registry, capacity, config or TwilioConfig.from_env(), transport)

    @application.post("/v1/calls", dependencies=[Depends(authenticate)])
    async def create_call(call: OutboundCall, request: Request):
        return await service.create(call, request.headers.get("idempotency-key", ""))

    @application.get("/v1/calls/{call_sid}", dependencies=[Depends(authenticate)])
    async def get_call(call_sid: str):
        return await service.call_status(call_sid)

    @application.get("/v1/call-attempts/{request_id}", dependencies=[Depends(authenticate)])
    async def get_attempt(request_id: str):
        return service.attempt_status(request_id)

    @application.delete("/v1/calls/{call_sid}", dependencies=[Depends(authenticate)])
    async def cancel_call(call_sid: str):
        return await service.call_status(call_sid, cancel=True)

    @application.post("/twilio/voice/{session_id}")
    async def voice(request: Request, session_id: str, turn: int = 0):
        if turn < 0 or turn > MAX_TURNS:
            raise HTTPException(422, "Invalid voice turn.")
        return await service.voice(request, session_id, turn)

    @application.post("/twilio/status/{session_id}")
    async def status(request: Request, session_id: str):
        return await service.status(request, session_id)

    return service
