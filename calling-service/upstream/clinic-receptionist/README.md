# AI clinic receptionist source review

Source: https://github.com/mohamedabdelaty74/AI-clinic-receptionist

Inspected commit: `a2e59eeef0438c83c7cecdc02280d3adfacf8670`.

This repository is a Python FastAPI receptionist application, not a trained
model or a downloadable set of weights. Its conversation engine uses Anthropic
Claude, multilingual Deepgram speech recognition, and gTTS speech output.
ElevenLabs is optional and disabled by default in the inspected source. Twilio
provides its phone transport. No license file appears in the inspected tree.
Venture includes an independent implementation of the observed orchestration;
no upstream source, assets, clinic data, or package installation scripts are
vendored here.

## Adaptation

`providers/clinic_receptionist.py` preserves the observed language selection,
short spoken replies, asynchronous Claude Messages API calls, conversation
history, tool-result continuation, and a maximum of five tool rounds from
`app/services/llm_brain.py`. It replaces the clinic appointment and knowledge
tools with a read-only tool that returns the exact context supplied for the
current Venture conversation. It does not create measurements or appointment
availability. The context remains request-local; the adapter does not write
transcripts or media. Provider failures are exposed as errors instead of
returning the upstream Arabic technical-error sentence as a successful reply.
Outbound turns marked `[venture outbound call]` and requests for an opening
message prepare a disclosed automated-assistant opening on the user's behalf,
using only the requested goal and supplied evidence. Generation itself neither
dispatches calls nor confirms bookings; those require external service results.

The running adapter requires server-side `ANTHROPIC_API_KEY`; its model comes
from `ProviderConfig.anthropic_model` (`CLINIC_ANTHROPIC_MODEL` in the calling service).
The upstream default is `claude-sonnet-4-20250514`. A configured key is not proof
that the remote model is available or that a live turn has succeeded.

## Upstream transports and limitations

The source exposes `POST /api/simulate` for text, `WS /demo/stream` for browser
PCM speech, and `POST /twilio/voice` plus `WS /twilio/stream` for phone audio. It
also exposes booking, doctor, slot, appointment, and call-log endpoints. Browser
speech responses are MP3. Phone responses should be 8 kHz mu-law; upstream uses
`ffmpeg` for conversion, but its fallback returns MP3 under the mu-law contract.
That fallback is unsuitable for an actual phone stream.

The unmodified source persists full transcripts in `logs/calls`, contains demo
clinic identities/prices, exposes its admin PIN in dashboard JavaScript, and has
no observed Twilio webhook-signature validation. Venture does not import those
endpoints, demo records, logs, or phone transport. This provider completes text
conversation turns. The shared calling service can connect those turns to its
separately configured, consent-gated Twilio gateway; it does not reuse the
upstream phone handler. Appointment booking, SMS, Deepgram streaming, and
upstream gTTS remain unavailable in this provider. A live call requires the
shared gateway's credentials and an explicit user opt-in and destination.

The upstream full application depends on FastAPI, uvicorn, websockets, httpx,
Twilio, Anthropic, pydantic settings, date utilities, numpy, and gTTS. Its optional
semantic retrieval uses sentence-transformers. The Venture adapter uses the
calling service's existing HTTP transport and needs no upstream package setup.

Focused mocked tests exercise the Claude tool loop, exact-context grounding,
missing configuration, invalid responses, request isolation, and loop limits.
They do not establish remote credential validity or clinical effectiveness.
