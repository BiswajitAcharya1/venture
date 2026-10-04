# rural-health-ai reference

Source: [MridulHarsh/rural-health-ai](https://github.com/MridulHarsh/rural-health-ai)
at inspected commit `c0d8e30636fd371c6e9760ab193fd6bcff938d4e`.

The source was read in a temporary checkout. No source code, disease profiles,
translations, or model weights from this repository are included here. No
upstream installation, training, Flutter build, or model inference was run.

## Actual upstream runtime

The application is a Flutter Android assistant for community health workers.
`android_app/lib/services/clinical_engine.dart` accepts symptoms and optional
vitals through `ClinicalEngine.diagnose`, computes clinical rule scores, and can
use TFLite output to adjust those scores. The repository includes a general
tabular classifier, six specialist classifiers, and four image classifiers.
These artifacts classify inputs; they do not generate conversation.

`android_app/pubspec.yaml` declares `tflite_flutter` and `speech_to_text`.
Speech recognition uses the device speech engine. There is no HTTP completion
API or calling server, and the offline workflow requires no API key.
`android_app/lib/services/handoff_service.dart` opens the platform dialer, SMS
composer, or WhatsApp using URL intents. Opening a dialer is not a completed
phone call or a confirmed appointment.

## Venture adaptation

`providers/rural_health_ai.py` is independently authored deterministic English
care-call intake code. It uses the upstream workflow ideas of distinguishing
reported concerns from supplied measurements, preserving absent evidence, and
ending with an explicit care handoff. It does not reproduce the diagnostic
scoring, disease knowledge, treatment recommendations, or emergency thresholds.

The provider declares `kind = "rules adaptation (no TFLite inference)"` and
`model = "deterministic care workflow"`. Its test button exercises this local
workflow. It does not claim to execute the upstream app or any TFLite model.
It neither places calls nor makes bookings, has no persistent conversation
state, and retains no voice recordings. Non-English requests fail explicitly.

For an explicitly marked outbound opening, the rules use the individual user's
requested goal and exact supplied evidence, then ask the clinic about its
appointment process. Subsequent recipient turns preserve that user's context
and direct identity or appointment-choice confirmation back to the user.

## License evidence

No `LICENSE` file was present at the inspected commit. The source README's
license section states that absent a license the project is all rights reserved
and pre-license. This integration therefore contains no upstream source or
weights. Redistribution or integration of those artifacts would require the
author's permission or a suitable published license.
