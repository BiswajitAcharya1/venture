# Nova Dear Care adaptation

Source: [DevDaring/Nova_Dear-Care](https://github.com/DevDaring/Nova_Dear-Care),
commit `69e82bc4ded3489377fa8323c37a917d7c9c271b`, authored by Team DevDaring.
The upstream README declares “MIT License — All code is original work by Team
DevDaring.” The inspected commit contains no standalone license file; this records
the declaration without inventing missing license text.

This repository supplies a Python 3.10 hardware assistant, not downloadable model
weights. `Code/aws_handler.py` calls Amazon Nova through Bedrock using native
`messages`, `system`, and `inferenceConfig` JSON. It bounds chat to 20 messages.
`Code/main.py` passes collected context to a brief spoken consultation. The
inspected source paths and commit are recorded in `provenance.json`; no upstream
application source is copied into Venture or imported or executed.

`providers/nova_dear_care.py` is an independently authored adaptation of that native
request/response and contextual-chat pattern. It makes a real `boto3` Bedrock
`invoke_model` call for AWS credentials or a native Invoke REST request for a
Bedrock bearer token, keeps history in the calling session, joins returned text
blocks, closes the response stream, and surfaces credential, timeout, model-access,
and malformed-response failures. It does not substitute an offline script after a
failed model call. The new prompt supports Venture appointment preparation and
`problem -> evidence -> next action`, with caller-supplied measured context, brief
language-specific responses, and no diagnostic probabilities or invented booking.
For a requested outbound opening, it drafts an individualized appointment request
from the caller's goal and opted-in context; it does not play the receiving clinic,
invent clinical labels, or confirm an appointment. Automated phone openings must
identify the automated assistant. Provider instructions are not a guarantee of
generated content and still require live evaluation with configured credentials.
Upstream RDK drivers, identity collection, audio-file recording, global history,
S3/Lambda encounter uploads, and persistent consultation notes are excluded.

Runtime requires server-side credentials with Bedrock model access and the calling
service's dependencies (`boto3` is used for AWS credential authentication). Static environment credentials,
`AWS_PROFILE`, SSO/role profiles, web identity, container credentials, and
`AWS_BEARER_TOKEN_BEDROCK` are recognized. Bearer requests use REST to avoid the
SDK's unnecessary metadata lookup when only a token is configured. Configuration inspection makes no metadata
request; a real response is required to verify authentication and inference.
Configure `NOVA_AWS_REGION` (default `us-east-1`) and
`NOVA_BEDROCK_MODEL_ID` for your region/profile. Although upstream uses unprefixed
`amazon.nova-2-lite-v1:0`, [AWS's Nova 2 documentation](https://docs.aws.amazon.com/nova/latest/nova2-userguide/core-inference.html)
lists `us.amazon.nova-2-lite-v1:0` and `global.amazon.nova-2-lite-v1:0` for inference.
The request format follows [AWS's Invoke API documentation](https://docs.aws.amazon.com/nova/latest/nova2-userguide/using-invoke-api.html).
Bedrock bearer tokens use [AWS's documented environment variable](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-use.html).

`tests/test_nova_dear_care.py` exercises native payloads, caller isolation, bounded
history, credential readiness, rejected unfinished responses, and sanitized SDK
failures with mocked AWS responses. Those checks do not establish a successful
live model call or the safety of generated medical content. No upstream install
or initialization script was executed during inspection.
