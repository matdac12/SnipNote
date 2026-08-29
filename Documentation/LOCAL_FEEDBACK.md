Below is a complete Markdown document you can copy into your repo (for example local_transcription_experiments.md).
It summarizes everything we discussed, adds implementation details for iOS, and explains the speed trick used by apps like MacWhisper.

⸻

:::writing{variant=“standard” id=“48219”}

Local Speech-to-Text on iOS (Whisper Stack Guide)

Goal

Improve local transcription in an iOS SwiftUI application by:
	•	fixing silence hallucinations
	•	improving accuracy
	•	increasing inference speed
	•	reducing memory footprint

The current implementation uses a basic Whisper pipeline without segmentation or VAD, which causes issues such as:
	•	repeated words
	•	hallucinated sentences
	•	poor silence detection
	•	inefficient compute usage

This document outlines a production-grade Whisper pipeline optimized for iOS.

⸻

1. Whisper Architecture Overview

Whisper consists of two independent parts:

Component	Description
Model	Neural network weights trained by OpenAI
Runtime	Software that runs inference on those weights

The original Whisper runtime is Python + PyTorch, which is not suitable for iOS.

Instead, mobile applications use:

whisper.cpp

This is a C/C++ implementation of Whisper designed for:
	•	CPU inference
	•	Metal acceleration
	•	quantized models
	•	mobile deployment

Repository:

https://github.com/ggerganov/whisper.cpp

⸻

2. Model Quantization

The original Whisper models are stored in float16 weights, which are too large for mobile devices.

Example model sizes:

Model	FP16 Size
Whisper Small	~466 MB
Whisper Medium	~1.5 GB
Whisper Large	~3 GB

To make them usable on mobile, models are quantized.

Quantization reduces the precision of weights and compresses the model.

Common formats:

Format	Bits	Use Case
Q8	8-bit	near-lossless
Q5	5-bit	best mobile tradeoff
Q4	4-bit	smaller but accuracy loss
Q2	2-bit	rarely useful

Typical sizes:

Model	Quantized Size
Whisper Small Q5	~190 MB
Whisper Small Q4	~150 MB

The recommended format for mobile is:

Q5_K_M

This is a newer block-quantization scheme that preserves accuracy while reducing memory.

⸻

3. Running Whisper on iOS

Typical local transcription stack:

whisper.cpp runtime
+
Whisper small Q5_K_M model
+
Metal acceleration

Pipeline:

Audio
 ↓
16kHz PCM conversion
 ↓
Mel spectrogram
 ↓
Encoder transformer
 ↓
Decoder token generation
 ↓
Text


⸻

4. Why Silence Causes Hallucinations

Without speech segmentation, Whisper processes long stretches of silence.

The decoder then tries to predict tokens even though no speech exists.

This leads to:
	•	repeated words
	•	nonsense phrases
	•	hallucinated sentences

Example failure case:

"yes yes yes yes yes yes yes yes yes yes"

This is extremely common when VAD is missing.

⸻

5. Voice Activity Detection (VAD)

The fix is VAD (Voice Activity Detection).

Instead of feeding the full audio to Whisper:

Audio
 ↓
VAD
 ↓
Speech segments
 ↓
Whisper transcription

Benefits:
	•	prevents hallucinations
	•	improves speed
	•	improves segmentation
	•	improves multilingual accuracy

Recommended VAD model:

Silero VAD

GitHub:

https://github.com/snakers4/silero-vad

Typical workflow:

audio
 ↓
detect speech segments
 ↓
split audio
 ↓
transcribe each segment


⸻

6. Beam Search Optimization

Default decoding parameters are not optimal.

Recommended parameters:

beam_size = 5
best_of = 5
temperature = 0

Benefits:
	•	improves word accuracy
	•	reduces hallucinations
	•	improves punctuation

Tradeoff:
	•	slightly slower inference.

⸻

7. Streaming Whisper

Instead of transcribing the entire file, Whisper can run incrementally.

Pipeline:

Audio stream
 ↓
Mel frame generation
 ↓
Decoder loop
 ↓
Partial transcripts

This enables near real-time transcription.

⸻

8. Speed Trick Used by MacWhisper and Similar Apps

Most developers run Whisper inefficiently.

Modern implementations accelerate inference using two main tricks.

⸻

Trick 1 — KV Cache Reuse

Whisper’s decoder is a transformer.

Transformers store attention keys and values:

K
V

During decoding, these values can be cached instead of recomputed.

Without caching:

O(n²)

With caching:

O(n)

whisper.cpp already implements KV caching internally.

But developers must avoid resetting the decoder state unnecessarily.

⸻

Trick 2 — Audio Chunk Batching

Instead of processing:

segment 1
segment 2
segment 3

each segment independently, better systems batch them.

batch(segment1, segment2, segment3)

This improves:
	•	CPU cache efficiency
	•	Metal GPU throughput
	•	decoder reuse

MacWhisper uses aggressive batching on Apple Silicon.

⸻

9. Recommended iOS Architecture

A production pipeline should look like this:

Audio input
 ↓
Resample to 16kHz mono
 ↓
Silero VAD
 ↓
Speech segmentation
 ↓
Batch segments
 ↓
whisper.cpp inference
 ↓
Decoder beam search
 ↓
Text output

Benefits:
	•	fewer hallucinations
	•	faster inference
	•	improved accuracy.

⸻

10. Shipping Models in an iOS App

Two strategies exist.

⸻

Strategy 1 — Download After Install (Your Current Method)

Workflow:

App install
 ↓
Download model
 ↓
Store in app sandbox

Pros:
	•	smaller App Store download
	•	can update models later

Cons:
	•	slower first experience
	•	requires network.

⸻

Strategy 2 — Bundle the Model

The model file can be included directly in the app bundle.

Steps:
	1.	Add model file to project:

whisper-small-q5_k_m.gguf

	2.	Drag into Xcode project.
	3.	Ensure Target Membership is enabled.
	4.	Access via Swift:

let modelURL = Bundle.main.url(
    forResource: "whisper-small-q5_k_m",
    withExtension: "gguf"
)

Then initialize Whisper:

let ctx = whisper_init_from_file(modelURL.path)

Pros:
	•	instant availability
	•	no download step
	•	predictable environment.

Cons:
	•	increases app binary size.

⸻

11. Recommended Model Choices for iPhone

Model	Recommendation
Whisper Small Q5	Best general option
Whisper Medium Q5	For high-end devices
Whisper Large	Not recommended

Typical RAM usage:

Model	RAM
Small Q5	~300-400MB
Medium Q5	~800MB
Large Q5	~1.6GB


⸻

12. Metal Acceleration

whisper.cpp supports Metal GPU acceleration.

Compile flag:

WHISPER_METAL=1

Performance improvement on modern iPhones:

Model	CPU	Metal
Small Q5	~1x realtime	~2-3x realtime


⸻

13. Practical Implementation Plan

Recommended experiments:
	1.	Integrate Silero VAD
	2.	Enable beam search decoding
	3.	Switch to Q5_K_M model
	4.	Enable Metal acceleration
	5.	Implement segment batching
	6.	Test streaming transcription

These steps should significantly improve:
	•	silence handling
	•	accuracy
	•	inference speed.

⸻

14. Expected Improvements

After applying the above optimizations:

Metric	Expected Improvement
Hallucinated text	drastically reduced
Transcription speed	2-4× faster
Silence detection	reliable
Memory usage	reduced


⸻

15. Key Takeaway

A naive Whisper pipeline performs poorly on mobile.

A production pipeline requires:

VAD
+
quantized models
+
optimized runtime
+
decoder tuning

When implemented correctly, Whisper can run near real-time on modern iPhones.

⸻

:::

⸻

Quick answer to your last question (outside the doc)

Yes — you can ship the model in the bundle, but only if the binary stays under App Store limits.

Typical limits today:
	•	4 GB max app size
	•	but 200–500 MB recommended

So a ~190 MB Whisper small Q5 model is usually fine to include.

Many apps do this.

However, your current download approach is also very common, because it allows:
	•	switching models
	•	adding languages later
	•	reducing initial app size.

⸻

If you’d like, I can also show you something extremely useful for your exact situation:

How to build a hybrid Whisper pipeline that automatically switches between:
	•	tiny for live transcription
	•	small for final high-accuracy transcription

This is what several top mobile transcription apps actually do, and it dramatically improves UX.