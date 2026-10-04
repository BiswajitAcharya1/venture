import os
from dataclasses import dataclass

import httpx


class ProviderError(Exception):
    def __init__(self, message: str, status_code: int = 502):
        super().__init__(message)
        self.status_code = status_code


@dataclass(frozen=True)
class ProviderConfig:
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-sonnet-4-20250514"
    aws_region: str = "us-east-1"
    nova_model: str = "us.amazon.nova-2-lite-v1:0"
    aws_profile: str = ""
    google_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"

    @classmethod
    def from_env(cls):
        return cls(
            anthropic_api_key=os.environ.get("ANTHROPIC_API_KEY", "").strip(),
            anthropic_model=os.environ.get("CLINIC_ANTHROPIC_MODEL", cls.anthropic_model),
            aws_region=os.environ.get("NOVA_AWS_REGION", os.environ.get("AWS_REGION", cls.aws_region)),
            nova_model=os.environ.get("NOVA_BEDROCK_MODEL_ID", cls.nova_model),
            aws_profile=os.environ.get("AWS_PROFILE", ""),
        )


async def post_json(url: str, *, headers: dict | None = None, body: dict) -> dict:
    # No redirects, request logging, transcript storage, or persistent cookies.
    try:
        async with httpx.AsyncClient(timeout=45, follow_redirects=False) as client:
            result = await client.post(url, headers=headers, json=body)
            if result.status_code in (401, 403):
                raise ProviderError("The model service rejected its credentials or model access.", 503)
            if result.status_code == 429:
                raise ProviderError("The model service is rate limited. Try again later.", 429)
            if result.status_code >= 300:
                raise ProviderError("The model service could not complete this request.")
            value = result.json()
            if not isinstance(value, dict):
                raise ProviderError("The model service returned an invalid response.")
            return value
    except (httpx.HTTPError, ValueError) as error:
        raise ProviderError("The model service is unreachable or returned an invalid response.") from error
