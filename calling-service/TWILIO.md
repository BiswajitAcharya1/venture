# Optional personalized phone calls

The service can place a real outbound Twilio call only after an authenticated
request includes `opted_in: true`. Each call opening uses the selected provider,
the caller's requested goal, and the exact supplied screening summary. The
recipient hears an automated-assistant disclosure and can say "stop" to end the
call. A phone call does not confirm a diagnosis, appointment, or clinic action.

No call was placed during implementation or automated tests.

## Server setup

Set these values on the server, never in the iOS app:

```dotenv
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=+...
TWILIO_PUBLIC_BASE_URL=https://your-public-host.example
```

The from number must support outbound Voice in the account. Trial accounts and
country permissions can restrict destinations. Use a reachable HTTPS server or
tunnel with a trusted certificate. An optional gateway prefix is supported if
the proxy strips that prefix before forwarding routes; for example the public
base can be `https://your-public-host.example/venture`. Avoid explicit ports,
URL credentials, query strings, and fragments in the base URL.

Run one service worker. Sessions are in memory, so independent workers or a
restart cannot resume a phone conversation. The service accepts at most 64
recent call attempts, clears personal session context after 15 minutes using
timers, and limits each phone conversation to 20 turns. Calls request a maximum
duration of 15 minutes. Minimal call-control/idempotency metadata expires after
30 minutes, allowing cancellation even if personal context has already expired.

## Client contract

`POST /v1/calls` uses the existing service bearer token:

```json
{
  "opted_in": true,
  "provider": "rural-health-ai",
  "to_number": "+15555550123",
  "language": "en",
  "context": "sleep duration: 5 hours; blood pressure: not supplied",
  "goal": "ask the selected clinic how to arrange a routine review of my sleep findings",
  "request_id": "one-uuid-per-intentional-call"
}
```

`provider` accepts `clinic-receptionist`, `nova-dear-care`, or `rural-health-ai`.
Phone speech currently supports English only. `context` is limited to 6,000
characters and `goal` to 1,000. A name is not required. Numbers must include a
country code in international E.164 format; this service accepts 8–15 digits.
The chosen cloud provider needs its own server-side credentials. Rural runs an
independent rules adaptation; it does not execute upstream TFLite classifiers.

Success returns only `provider`, `call_sid`, and Twilio's call `status`. Opening
generation happens before the REST request that dials. Failed generation places
no call. Keep the same `request_id` for retries of one intent; a different
payload with that id fails. A timeout while dialing has an unknown outcome and
must not cause a new dial. Retrying the same id checks the existing attempt.
`Idempotency-Key` can be used instead, or must match if both are provided.

Authenticated `GET /v1/calls/{call_sid}` checks a call created by this process;
`DELETE /v1/calls/{call_sid}` requests cancellation or hangup and clears its
personal context. A finished or expired session cannot resume. The response
does not include phone numbers, transcripts, or screening measurements.

Authenticated `GET /v1/call-attempts/{request_id}` returns the same minimal
metadata even when a dial response was lost. `failed` with no call SID indicates
a known pre-dial failure or definitive Twilio rejection; `unknown` indicates a
possible dial and must preserve the original intent id. A subsequent signed
Twilio callback can recover the call SID. Twilio server errors are treated as
unknown outcomes. A missing/expired attempt returns 404.

## Webhooks and data lifetime

Twilio receives unique opaque URLs at `/twilio/voice/{session_id}` and
`/twilio/status/{session_id}`. Every webhook requires a valid Twilio HMAC
signature computed against the configured public URL, exact query string, and
all form fields. Account and call identifiers are checked separately. Arbitrary
Host headers do not select the public signing origin. Speech turns use
`Gather input="speech"`, and generated text is XML escaped. Cached turn
responses make webhook retries idempotent.

The service does not request recordings or transcription resources, write
transcripts to disk, or log request bodies. Twilio still processes the phone
audio for speech recognition and may retain its own call metadata or webhook
debug data under the account's settings. Selected cloud providers also process
the submitted text. The service keeps only bounded conversation text and the
supplied summary in RAM, clearing them on completion, stop, cancellation,
failure, or expiry. Tiny call-status/idempotency metadata remains for at most
30 minutes and contains no phone number, summary, or transcript.

Live speech replies have a 10-second model timeout because Twilio Voice
webhooks have a hard 15-second limit. A slow or unavailable model receives a
spoken failure and a hangup; an opening can take up to 60 seconds before dialing.

Reference contracts: [Twilio Call resource](https://www.twilio.com/docs/voice/api/call-resource),
[Gather](https://www.twilio.com/docs/voice/twiml/gather),
[webhook security](https://www.twilio.com/docs/usage/security), and
[Voice webhook time limits](https://www.twilio.com/docs/usage/webhooks/webhooks-connection-overrides).
