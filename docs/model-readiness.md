# Model readiness

A disease-specific screening result requires an executable mobile artifact,
identical preprocessing, a compatible runtime, redistribution rights,
held-out validation for that artifact and recording protocol, and proof that
recorded user input reaches the model. Model-loading tests alone do not meet
these requirements.

The current voice flow runs local descriptive acoustic analysis and the
bundled Silero VAD Core ML model on compatible devices. A simulator signal gate
is explicitly labeled as a fallback. Optional Apple on-device Speech provides
word count and lexical diversity when supported for the selected language.
No raw audio or transcript is saved in screening history.

The historical 22-feature Parkinson Core ML artifact is retained for
provenance but its inference path is disabled: the prior extractor assigned
unrelated statistics to MDVP/nonlinear feature names. The app-native
Alzheimer/dementia and voice mood composite formulas are not validated disease
heads and are excluded from public screening results. Eye tests produce no
current result.

SSL4PR publishes trained Parkinson speech research checkpoints with a
MIT-labeled model card. The separate [voice model audit](voice-model-audit.md)
tracks the exact Core ML conversion, preprocessing and parity checks. Any
successful execution is a research-dataset pattern result for the documented
source task/language only, never a personal disease probability, diagnosis,
or dementia-subtype result. Clinical iPhone validation remains a separate
requirement before disease screening can be advertised.

WavBERT has a training pipeline without a released deployable Alzheimer task
head. OPERA and Google HeAR publish acoustic representations that require
separate downstream classifiers; neither embedding is a disease result.

The bundled LFM2.5 GGUF through llama.cpp remains a local companion model,
reported as running only after a successful real decode. It explains measured
context and does not supply diagnostic disease probabilities.

Before archive, run `./tools/verify_model_artifacts.sh`, the relevant runtime
tests, and the full `VentureTests` suite. Never substitute placeholder data for
missing disease-specific output.
