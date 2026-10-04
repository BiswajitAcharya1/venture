# Voice model audit

Reviewed 2026-10-03. Primary repositories and author model cards were inspected,
not social-media demonstrations. This file records executable boundaries and
must be updated with the actual conversion result before claiming integration.

| Source | Published material | Current boundary |
| --- | --- | --- |
| [SSL4PR](https://github.com/K-STMLab/SSL4PR) / [official full HuBERT checkpoint](https://huggingface.co/morenolq/SSL4PR-hubert-base-full) | Trained custom-head PyTorch checkpoint; author model card labels weights MIT | Core ML conversion in progress; not yet represented as running |
| [WavBERT](https://github.com/billzyx/WavBERT) | ADReSSo training/evaluation, wav2vec ASR + BERT and pause/embedding conversion | No released Alzheimer task head or iOS export; unavailable |
| [OPERA](https://github.com/evelyn0414/OPERA) | MIT research code and released respiratory representation checkpoints | Requires a downstream task head, original waveform/spectrogram preprocessing, and matching respiratory protocol; unavailable |
| [Google HeAR](https://github.com/Google-Health/hear) | Apache-2.0 repository; health-audio embedding model distributed separately | Embeddings are not condition labels; no compatible mobile disease head bundled |
| [legacy Parkinson feature classifier](https://github.com/nkmohit/Parkinsons-Disease-Detection) | MIT demonstration classifier using 22 named features | Mobile feature contract unverified; inference blocked |

## SSL4PR reproducibility record

- Source revision: `7fc5b9109371ab9c2f48d7411f8b40b06f3db097`.
- Full HuBERT model revision: `b02b648920cfbe3eef0a98c683c2a71a17dfb606`.
- Exact released filename: `model_best.pt` (the model-card prose says `model.pt`,
  but the file listing and downloaded artifact use `model_best.pt`).
- Model card licenses the checkpoint as MIT. The underlying HuBERT model and
  conversion libraries retain their separate upstream licenses. No unlicensed
  upstream Python source is added to the distributed application.
- Architecture includes the HuBERT base encoder, thirteen learned layer
  weights, per-layer normalization, learned attention pooling, two 768-unit
  ReLU layers and a one-unit sigmoid research-label head. The exported model
  must contain these trained parameters, not an untrained substitute.
- Upstream configuration uses 16 kHz mono float audio, no feature-extractor
  amplitude normalization (`do_normalize=False`), up to 10 seconds, zero
  padding/truncation, and no inference attention mask passed into the encoder.
- The full model was trained on s-PC-GITA and evaluated on e-PC-GITA. The
  official evaluation code covers DDK1, monologue and readtext in the source
  Spanish speech domain. A sustained vowel is not an interchangeable task.
  The initial app contract therefore requires a separate Spanish monologue.
- The author's pinned `test_results.txt` reports raw-audio accuracy 75.83%,
  sensitivity 90.00%, specificity 61.67%; enhanced-audio accuracy 86.67%,
  sensitivity 81.67%, specificity 91.67%. These are author research-corpus
  results, not validation of an exported Core ML artifact or iPhone users.
  The raw path does not claim the enhancement result.

## Measured acoustic path

The sustained vowel is analyzed locally with a YIN-style cumulative normalized
difference function to estimate the fundamental frequency (55–500 Hz), not
all harmonic spectral peaks. Windowed-sinc resampling limits aliasing before
analysis at 8 kHz. 64 ms frames advance by 20 ms; voiced time counts the hop,
not the entire overlapping frame. Pitch/amplitude variation are coefficients
of variation across voiced frames, explicitly not cycle-level jitter/shimmer.

Finite input, duration, signal periodicity, clipping and recording quality
are checked. The shared usable-recording rule requires quality >= 0.55,
voiced time >= 1.5 seconds and clipping < 3%. These are engineering capture
rules and are not clinical cutoffs. Poor recordings may show retake guidance
but never produce a disease conclusion or baseline-change interpretation.
