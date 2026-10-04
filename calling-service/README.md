# Venture calling experiments

The care page has one test button for each supplied repository. They have independent conversation state and removable test cards. These repositories are application pipelines, not three interchangeable conversational weight files.

| Button | Executed adaptation | Configuration |
| --- | --- | --- |
| ai clinic receptionist | Claude message API with the source's bounded tool continuation, adapted read-only Venture context tool and appointment purpose | `ANTHROPIC_API_KEY`; optional `CLINIC_ANTHROPIC_MODEL` |
| nova dear care | Amazon Nova native Bedrock invocation with bounded history and personalized appointment context | AWS credentials/profile or `AWS_BEARER_TOKEN_BEDROCK`, region and accessible inference profile |
| rural health ai | Independently authored English evidence/intake/appointment rules informed by the source's workflow | No model key. **No upstream TFLite inference** |

Each source is pinned in its `upstream/*/README.md`. The first and third have no published license; Nova's README claims MIT without a license file. This implementation does not copy their application code or distribute their weights. Source, compatibility and licensing limitations are recorded with the adapters.

## Start

Use Python 3.10 or later. Vendor credentials belong in the service, never the iOS binary.

```sh
cd calling-service
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
cp .env.example .env
.venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))'
```

Put the generated token in `.env` as `VENTURE_CALL_SERVICE_TOKEN`; configure whichever cloud provider you want to test. Then:

```sh
.venv/bin/python -m uvicorn app:app --env-file .env --host 127.0.0.1 --port 8765 --no-access-log
```

For this Codex workspace, `/tmp/venture-calling-venv` already contains the dependencies. This development environment's bundled Python is `/Users/paresh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`.

In **care → calling service**, enter your service URL and token, then **check service**. A Debug simulator can use `http://127.0.0.1:8765`; a physical iPhone or Release build needs your reachable HTTPS deployment. The server token remains in app memory for the session. Only the URL and hidden test choices persist.

## Compare and personalize

Open any test and type a message or dictate on device. **personalize this conversation → share measured summary** displays exactly what will be sent. Add an appointment goal and press **start personalized demo** to generate the opening automatically from that user's recorded values. Missing measurements remain unavailable. Turning sharing off resets conversation history, so prior evidence is not sent again in later turns.

Responses are read using an installed iOS voice when available. On-device dictation and voice availability vary by language; typing remains available. Rural's rules adaptation supports English only.

The cards distinguish service configuration from a received response, report the latest response time, and expose a **remove test** menu. **restore all tests** reverses card removal. To permanently remove an experiment, remove its provider from the service registry and its case from `VentureCallExperiment`.

## Real calls

Optional signed Twilio outbound calls use the same selected provider and frozen personal summary. See [TWILIO.md](TWILIO.md). The app requires an explicit automated-call opt-in and destination number. The assistant introduces itself, gathers the clinic's speech replies, and must let the clinic confirm availability. The code does not record calls or persist transcripts; Twilio and model providers process the data necessary for their services.

Call request IDs prevent retrying a lost response from creating a duplicate telephone call. Status/end controls remain available after closing and reopening a test during the same app session. Keep the service running in one worker because call-session state is intentionally in memory; restart expires sessions. For a hackathon demo, prefer a consenting team member's test number.

## Verify

```sh
.venv/bin/python -m unittest discover -s tests -v
```

Provider transport tests use mocked responses. A passing test or configured key is not proof of live model access. Cloud inference and real telephone delivery require accessible accounts, provider credentials and a reachable public webhook URL.
