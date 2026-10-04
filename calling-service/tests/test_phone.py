import asyncio
import base64
import hashlib
import hmac
import time
import unittest
import xml.etree.ElementTree as ET
from urllib.parse import parse_qs, urlencode, urlsplit
from unittest.mock import AsyncMock

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.testclient import TestClient

from phone import TTL, TwilioConfig, install_phone_routes, signature
from providers.base import ProviderError


ACCOUNT = "AC" + "a" * 32
SID = "CA" + "b" * 32
TOKEN = "test-auth-token-not-a-real-credential"
BASE = "https://calls.example.test"
AUTH = {"Authorization": "Bearer test-service-token"}


class Provider:
    id = "rural-health-ai"
    configured = True
    unavailable_reason = ""

    def __init__(self):
        self.complete = AsyncMock(return_value="your supplied sleep evidence is 5 hours. what next step suits you? <safe & escaped>")


class PhoneTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        self.provider = Provider()
        self.config = TwilioConfig(ACCOUNT, TOKEN, "+15555550100", BASE)
        self.http_error = None
        self.resource_status = "queued"

        def transport(request):
            self.requests.append(request)
            if self.http_error:
                raise self.http_error
            status = self.resource_status
            data = parse_qs(request.content.decode())
            if "Status" in data:
                status = data["Status"][0]
            return httpx.Response(201 if request.method == "POST" else 200,
                                  json={"sid": SID, "status": status})

        def authenticate(request: Request):
            if request.headers.get("authorization") != AUTH["Authorization"]:
                raise HTTPException(401, "Missing service token")

        self.app = FastAPI()
        self.service = install_phone_routes(self.app, {self.provider.id: self.provider}, authenticate,
                                            asyncio.Semaphore(4), config=self.config,
                                            transport=httpx.MockTransport(transport))
        self.client = TestClient(self.app)
        self.client.__enter__()

    def tearDown(self):
        self.service.close()
        self.client.__exit__(None, None, None)

    def payload(self, **overrides):
        return {"opted_in": True, "provider": self.provider.id, "to_number": "+15555550123",
                "language": "en", "goal": "discuss my sleep evidence", "context": "sleep duration: 5 hours",
                "request_id": "intent-1", **overrides}

    def create(self, **overrides):
        return self.client.post("/v1/calls", json=self.payload(**overrides), headers=AUTH)

    def session_id(self):
        return next(iter(self.service.sessions))

    def webhook(self, path, fields=None, valid=True):
        fields = {"AccountSid": ACCOUNT, "CallSid": SID, **(fields or {})}
        # Compute independently of production's helper, preserving all fields.
        public_url = self.service.config.public_base_url.rstrip("/") + path
        source = public_url + "".join(key + str(fields[key]) for key in sorted(fields))
        signed = base64.b64encode(hmac.new(TOKEN.encode(), source.encode(), hashlib.sha1).digest()).decode()
        return self.client.post(path, content=urlencode(fields), headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "X-Twilio-Signature": signed if valid else "invalid",
        })

    def test_explicit_boolean_opt_in_required_before_provider_or_dial(self):
        for consent in (False, "true", 1):
            with self.subTest(consent=consent):
                self.assertEqual(self.create(opted_in=consent).status_code, 422)
        payload = self.payload()
        del payload["opted_in"]
        self.assertEqual(self.client.post("/v1/calls", json=payload, headers=AUTH).status_code, 422)
        self.provider.complete.assert_not_awaited()
        self.assertEqual(self.requests, [])

    def test_phone_routes_require_service_auth(self):
        self.assertEqual(self.client.post("/v1/calls", json=self.payload()).status_code, 401)
        self.create()
        self.assertEqual(self.client.get(f"/v1/calls/{SID}").status_code, 401)
        self.assertEqual(self.client.delete(f"/v1/calls/{SID}").status_code, 401)

    def test_invalid_number_and_language_never_dial(self):
        for number in ("555-555-0123", "15555550123", "+123", "+05555550123", "+15555550123456789"):
            self.assertEqual(self.create(to_number=number).status_code, 422)
        self.assertEqual(self.create(language="hi").status_code, 422)
        self.assertEqual(self.requests, [])

    def test_personalized_opening_runs_before_twilio_and_never_requests_recording(self):
        response = self.create()
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(set(response.json()), {"provider", "call_sid", "status"})
        self.assertEqual(response.json()["call_sid"], SID)
        messages, language, context = self.provider.complete.await_args.args
        self.assertIn("discuss my sleep evidence", messages[0]["content"])
        self.assertIn("Generate the opening message", messages[0]["content"])
        self.assertEqual(context, "sleep duration: 5 hours")
        self.assertEqual(language, "en")
        self.assertEqual(len(self.requests), 1)
        form = parse_qs(self.requests[0].content.decode())
        self.assertEqual(form["To"], ["+15555550123"])
        self.assertEqual(form["From"], ["+15555550100"])
        self.assertEqual(form["TimeLimit"], [str(TTL)])
        self.assertEqual(form["StatusCallbackEvent"], ["initiated", "ringing", "answered", "completed"])
        self.assertNotIn("Record", form)
        self.assertNotIn("Transcribe", form)
        self.assertNotIn("context", form)
        self.assertNotIn("sleep", form["Url"][0])

    def test_different_context_and_goal_are_propagated_without_cross_call_history(self):
        self.create()
        response = self.create(request_id="intent-2", goal="discuss my recall evidence", context="recall: 2 of 5")
        self.assertEqual(response.status_code, 200)
        arguments = self.provider.complete.await_args.args
        self.assertIn("discuss my recall evidence", arguments[0][0]["content"])
        self.assertNotIn("sleep", arguments[0][0]["content"])
        self.assertEqual(arguments[2], "recall: 2 of 5")
        urls = [parse_qs(request.content.decode())["Url"][0] for request in self.requests]
        self.assertNotEqual(urls[0], urls[1])

    def test_repeat_intent_does_not_generate_or_dial_again(self):
        first = self.create()
        second = self.create()
        self.assertEqual(first.json(), second.json())
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(self.provider.complete.await_count, 1)

    def test_same_id_with_different_details_is_rejected(self):
        self.create()
        for changed in ({"context": "recall: 2 of 5"}, {"to_number": "+15555550124"}, {"goal": "something else"}):
            self.assertEqual(self.create(**changed).status_code, 409)
        self.assertEqual(len(self.requests), 1)

    def test_failed_opening_never_dials_and_error_is_sanitized(self):
        self.provider.complete.side_effect = RuntimeError("secret transcript and credential")
        response = self.create()
        self.assertEqual(response.status_code, 502)
        self.assertIn("no call was placed", response.text)
        self.assertNotIn("secret", response.text)
        self.assertEqual(self.requests, [])
        self.assertEqual(self.service.sessions, {})

    def test_unconfigured_twilio_never_generates_or_dials(self):
        self.service.config = TwilioConfig()
        self.assertEqual(self.create().status_code, 503)
        self.provider.complete.assert_not_awaited()
        self.assertEqual(self.requests, [])

    def test_unconfigured_provider_never_dials(self):
        self.provider.configured = False
        self.provider.unavailable_reason = "not configured"
        self.assertEqual(self.create().status_code, 503)
        self.assertEqual(self.requests, [])

    def test_ambiguous_rest_timeout_is_not_retried(self):
        self.http_error = httpx.ReadTimeout("unknown outcome")
        first = self.create()
        self.assertEqual(first.status_code, 502)
        self.assertIn("unknown", first.text)
        self.assertEqual(self.create().status_code, 409)
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(self.provider.complete.await_count, 1)
        self.assertEqual(len(self.service.sessions), 1)
        self.assertEqual(self.client.get("/v1/call-attempts/intent-1", headers=AUTH).json()["status"], "unknown")

    def test_attempt_status_is_authenticated_and_recovers_pre_dial_failure(self):
        self.provider.complete.side_effect = ProviderError("not configured", 503)
        self.assertEqual(self.create().status_code, 503)
        self.assertEqual(self.client.get("/v1/call-attempts/intent-1").status_code, 401)
        response = self.client.get("/v1/call-attempts/intent-1", headers=AUTH)
        self.assertEqual(response.json(), {"provider": "rural-health-ai", "call_sid": "", "status": "failed"})
        self.assertEqual(self.requests, [])

    def test_twilio_server_error_is_unknown_and_never_retried(self):
        requests = []
        def failure(request):
            requests.append(request)
            return httpx.Response(500, json={"message": "secret server failure"})
        self.service.transport = httpx.MockTransport(failure)
        self.assertEqual(self.create().status_code, 502)
        self.assertEqual(self.create().status_code, 409)
        self.assertEqual(len(requests), 1)
        self.assertEqual(self.client.get("/v1/call-attempts/intent-1", headers=AUTH).json()["status"], "unknown")

    def test_twilio_client_rejection_is_known_failed_without_session(self):
        self.service.transport = httpx.MockTransport(lambda request: httpx.Response(400, json={"message": "bad number"}))
        self.assertEqual(self.create().status_code, 502)
        self.assertEqual(self.client.get("/v1/call-attempts/intent-1", headers=AUTH).json()["status"], "failed")
        self.assertEqual(self.service.sessions, {})

    def test_twilio_documented_signature_vector(self):
        form = {"CallSid": ["CA1234567890ABCDE"], "Caller": ["+14158675310"], "Digits": ["1234"],
                "From": ["+14158675310"], "To": ["+18005551212"]}
        self.assertEqual(signature("12345", "https://example.com/myapp.php?foo=1&bar=2", form),
                         "L/OH5YylLD5NRKLltdqwSvS0BnU=")

    def test_unsigned_or_bad_signature_cannot_reveal_opening_or_run_provider(self):
        self.create()
        path = f"/twilio/voice/{self.session_id()}"
        response = self.webhook(path, valid=False)
        self.assertEqual(response.status_code, 403)
        self.assertNotIn("sleep", response.text)
        self.assertEqual(self.provider.complete.await_count, 1)
        self.assertEqual(self.client.post(path, data={"SpeechResult": "hello"}).status_code, 403)

    def test_signed_voice_discloses_automation_and_escapes_xml(self):
        self.create()
        response = self.webhook(f"/twilio/voice/{self.session_id()}", {"FutureField": "  extra value "})
        self.assertEqual(response.status_code, 200, response.text)
        document = ET.fromstring(response.text)
        say = document.find("Gather/Say").text
        self.assertIn("automated care assistant", say)
        self.assertIn("<safe & escaped>", say)
        self.assertIn("&lt;safe &amp; escaped&gt;", response.text)
        self.assertEqual(document.find("Gather").attrib["input"], "speech")
        self.assertNotIn("Record", response.text)

    def test_signature_binds_exact_query_and_account_and_call(self):
        self.create()
        path = f"/twilio/voice/{self.session_id()}"
        self.assertEqual(self.webhook(path, {"AccountSid": "AC" + "c" * 32}).status_code, 403)
        self.assertEqual(self.webhook(path, {"CallSid": "CA" + "c" * 32}).status_code, 403)
        self.assertEqual(self.webhook(path + "?turn=0").status_code, 200)

    def test_speech_turn_is_two_way_and_retry_does_not_duplicate_history(self):
        self.create()
        session_id = self.session_id()
        self.webhook(f"/twilio/voice/{session_id}")
        self.provider.complete.return_value = "which clinic should we contact?"
        path = f"/twilio/voice/{session_id}?turn=1"
        response = self.webhook(path, {"SpeechResult": "what about a routine appointment?"})
        self.assertEqual(response.status_code, 200)
        self.assertIn("which clinic", response.text)
        arguments = self.provider.complete.await_args.args
        self.assertEqual(arguments[0][-1], {"role": "user", "content": "what about a routine appointment?"})
        self.assertEqual(arguments[2], "sleep duration: 5 hours")
        count = self.provider.complete.await_count
        duplicate = self.webhook(path, {"SpeechResult": "what about a routine appointment?"})
        self.assertEqual(duplicate.text, response.text)
        self.assertEqual(self.provider.complete.await_count, count)
        self.assertEqual(self.webhook(path, {"SpeechResult": "different text"}).status_code, 409)

    def test_stop_immediately_clears_personal_state_and_hangs_up(self):
        self.create()
        session_id = self.session_id()
        retained_reference = self.service.sessions[session_id]
        self.webhook(f"/twilio/voice/{session_id}")
        response = self.webhook(f"/twilio/voice/{session_id}?turn=1", {"SpeechResult": "please stop"})
        self.assertIn("Hangup", response.text)
        self.assertNotIn(session_id, self.service.sessions)
        self.assertEqual(retained_reference.messages, [])
        self.assertEqual(retained_reference.context, "")

    def test_signed_terminal_status_clears_state_and_old_progress_cannot_restore_it(self):
        self.create()
        session_id = self.session_id()
        path = f"/twilio/status/{session_id}"
        self.assertEqual(self.webhook(path, {"CallStatus": "completed"}, valid=False).status_code, 403)
        self.assertIn(session_id, self.service.sessions)
        self.assertEqual(self.webhook(path, {"CallStatus": "completed"}).status_code, 204)
        self.assertNotIn(session_id, self.service.sessions)
        self.assertEqual(self.webhook(path, {"CallStatus": "ringing"}).status_code, 204)
        self.assertEqual(self.create().json()["status"], "completed")

    def test_expiry_deletes_personal_state_without_persistent_transcripts(self):
        self.create()
        key = next(iter(self.service.attempts))
        session = self.service.sessions[self.session_id()]
        self.service.attempts[key].expires_at = time.monotonic() - 1
        self.service.purge()
        self.assertEqual(self.service.sessions, {})
        self.assertEqual(self.service.attempts, {})
        self.assertEqual(self.service.calls, {})
        self.assertEqual(session.context, "")
        self.assertEqual(session.messages, [])

    def test_authenticated_status_and_cancel_return_minimal_metadata(self):
        self.create()
        self.assertEqual(self.client.get(f"/v1/calls/{SID}", headers=AUTH).json()["status"], "queued")
        response = self.client.delete(f"/v1/calls/{SID}", headers=AUTH)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "canceled")
        self.assertEqual(set(response.json()), {"provider", "call_sid", "status"})
        self.assertEqual(self.service.sessions, {})
        self.assertEqual(parse_qs(self.requests[-1].content.decode()), {"Status": ["canceled"]})

    def test_failed_followup_ends_call_and_clears_context(self):
        self.create()
        session_id = self.session_id()
        self.webhook(f"/twilio/voice/{session_id}")
        self.provider.complete.side_effect = ProviderError("not available")
        response = self.webhook(f"/twilio/voice/{session_id}?turn=1", {"SpeechResult": "hello"})
        self.assertEqual(response.status_code, 200)
        self.assertIn("Hangup", response.text)
        self.assertEqual(self.service.sessions, {})

    def test_public_origin_rejects_unsafe_or_ambiguous_urls(self):
        for base in ("http://calls.example.test", "https://user:secret@calls.example.test", "https://localhost",
                     "https://127.0.0.1", "https://calls.example.test?secret=x", "https://calls.example.test:443"):
            self.assertTrue(TwilioConfig(ACCOUNT, TOKEN, "+15555550100", base).unavailable_reason)
        self.assertEqual(TwilioConfig(ACCOUNT, TOKEN, "+15555550100", BASE + "/gateway").unavailable_reason, "")

    def test_gateway_prefix_signature_uses_external_public_url(self):
        self.service.config = TwilioConfig(ACCOUNT, TOKEN, "+15555550100", BASE + "/gateway")
        self.create()
        response = self.webhook(f"/twilio/voice/{self.session_id()}")
        self.assertEqual(response.status_code, 200, response.text)

    def test_gateway_asgi_root_path_is_not_duplicated_in_signature(self):
        self.service.config = TwilioConfig(ACCOUNT, TOKEN, "+15555550100", BASE + "/gateway")
        self.create()
        session_id = self.session_id()
        fields = {"AccountSid": ACCOUNT, "CallSid": SID}
        public_path = f"/gateway/twilio/voice/{session_id}"
        source = BASE + public_path + "".join(key + fields[key] for key in sorted(fields))
        signed = base64.b64encode(hmac.new(TOKEN.encode(), source.encode(), hashlib.sha1).digest()).decode()
        with TestClient(self.app, root_path="/gateway") as gateway_client:
            response = gateway_client.post(public_path, content=urlencode(fields), headers={
                "Content-Type": "application/x-www-form-urlencoded", "X-Twilio-Signature": signed,
            })
        self.assertEqual(response.status_code, 200, response.text)

    def test_long_conversation_keeps_original_goal_and_recipient_role(self):
        self.create()
        session_id = self.session_id()
        self.webhook(f"/twilio/voice/{session_id}")
        self.provider.complete.return_value = "please explain the next appointment step."
        for turn in range(1, 8):
            response = self.webhook(f"/twilio/voice/{session_id}?turn={turn}", {"SpeechResult": f"clinic reply {turn}"})
            self.assertEqual(response.status_code, 200)
        messages = self.provider.complete.await_args.args[0]
        self.assertIn("discuss my sleep evidence", messages[0]["content"])
        self.assertIn("clinic staff", messages[0]["content"])
        self.assertIn("not the recipient", messages[0]["content"])
        self.assertLessEqual(len(messages), 13)
        self.assertLessEqual(len(self.service.sessions[session_id].messages), 10)

    async def signed_async_status(self, session_id, status):
        path = f"/twilio/status/{session_id}"
        fields = {"AccountSid": ACCOUNT, "CallSid": SID, "CallStatus": status}
        source = BASE + path + "".join(key + fields[key] for key in sorted(fields))
        signed = base64.b64encode(hmac.new(TOKEN.encode(), source.encode(), hashlib.sha1).digest()).decode()
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=self.app), base_url="http://testserver") as client:
            response = await client.post(path, content=urlencode(fields), headers={
                "Content-Type": "application/x-www-form-urlencoded", "X-Twilio-Signature": signed,
            })
        self.assertEqual(response.status_code, 204)

    def test_terminal_callback_wins_over_stale_status_fetch(self):
        self.create()
        session_id = self.session_id()
        async def race(request):
            await self.signed_async_status(session_id, "completed")
            return httpx.Response(200, json={"sid": SID, "status": "ringing"})
        self.service.transport = httpx.MockTransport(race)
        response = self.client.get(f"/v1/calls/{SID}", headers=AUTH)
        self.assertEqual(response.json()["status"], "completed")
        self.assertEqual(self.service.sessions, {})

    def test_signed_callback_recovers_lost_create_response_without_retry(self):
        async def race(request):
            session_id = self.session_id()
            await self.signed_async_status(session_id, "completed")
            raise httpx.ReadTimeout("lost create response")
        self.service.transport = httpx.MockTransport(race)
        response = self.create()
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["status"], "completed")
        self.assertEqual(response.json()["call_sid"], SID)
        self.assertEqual(self.service.sessions, {})
        self.assertEqual(self.create().json(), response.json())

    def test_personal_expiry_preserves_minimal_cancel_control(self):
        self.create()
        session_id = self.session_id()
        session = self.service.sessions[session_id]
        session.expires_at = time.monotonic() - 1
        self.service.purge()
        self.assertEqual(self.service.sessions, {})
        self.assertEqual(session.context, "")
        self.assertEqual(session.initial_request, "")
        status = self.client.get("/v1/call-attempts/intent-1", headers=AUTH)
        self.assertEqual(status.json()["call_sid"], SID)
        self.assertEqual(self.client.delete(f"/v1/calls/{SID}", headers=AUTH).json()["status"], "canceled")

    def test_late_signed_callback_recovers_unknown_call_after_context_expiry(self):
        self.http_error = httpx.ReadTimeout("unknown create outcome")
        self.assertEqual(self.create().status_code, 502)
        session_id = self.session_id()
        self.service.sessions[session_id].expires_at = time.monotonic() - 1
        self.service.purge()
        self.assertEqual(self.service.sessions, {})
        response = self.webhook(f"/twilio/status/{session_id}", {"CallStatus": "ringing"})
        self.assertEqual(response.status_code, 204)
        response = self.client.get("/v1/call-attempts/intent-1", headers=AUTH)
        self.assertEqual(response.json()["call_sid"], SID)
        self.assertEqual(response.json()["status"], "ringing")
        self.assertEqual(self.service.sessions, {})
        voice = self.webhook(f"/twilio/voice/{session_id}")
        self.assertIn("Hangup", voice.text)
        self.assertNotIn("sleep", voice.text)


if __name__ == "__main__":
    unittest.main()
