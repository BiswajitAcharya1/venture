# Venture Engineering Guide

Keep this file short. The code and tests are the source of truth; documentation
must describe current behavior and must not promise planned features.

## Product Rules

- Build a native iOS app that turns measured signals into:
  `problem -> evidence -> next action`.
- Never invent measurements, model output, permissions, or availability.
- Treat health outputs as screening context, not diagnosis or certainty.
- Store extracted metrics only. Do not retain camera frames or voice recordings.
- Prefer calm, curved, restrained SwiftUI over dashboard-style layouts.
- Keep visible product copy lowercase unless platform or legal conventions differ.

## Implementation Rules

- Extend `VentureStore`, `MentalHealthCore`, and the existing sensor services.
- Keep model state honest: active only when the artifact loads and executes.
- Put runtime contracts in code, focused comments, and tests, not large specs.
- Keep edits scoped and preserve unrelated user changes.
- Use strong reasoning for medical, security, model-integration, and architecture work.

## Verification

Run:

```sh
swiftc -parse $(rg --files Venture VentureTests -g '*.swift')
./tools/build_simulator_clean.sh
```

Then run the relevant simulator tests and the full `VentureTests` suite. For UI
changes, inspect and interact with the actual simulator screen.
