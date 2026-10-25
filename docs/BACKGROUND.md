# Background latency investigation — 0.1.3

## Observed, not assumed

User tested iPhone 14 Pro / iOS 27 / SideStore installation with USB video.
Inside the app the picture felt nearly immediate. On leaving the app or opening
notifications it became slow. The supplied 0.1.2 console excerpt showed RX down
to 5.8 FPS and the old encoder field up to 399.9 ms. Neither proves display
latency: the old encoder field included waiting for the encode queue after the
VideoToolbox callback. The excerpt does not isolate heat, OS scheduling, game
load, conversion or transport as the root cause.

## Changes in this experiment

- Capture, encoding and USB queues request userInteractive QoS. This is a
  scheduling request, not a guarantee of background execution priority.
- Keep ScreenCaptureKit defaults and the existing 60 FPS admission ceiling.
  Resolution still fits within 1280×720, aspect preserved. The actual Xcode 27.1
  SDK rejects minimumFrameInterval and queueDepth on iOS despite the web pages
  listing iOS availability. This was verified by CI; neither property is used.
- Request VideoToolbox low-latency rate control at session creation, with High
  profile, no B frames, real-time compression and optional speed-over-quality.
  The low-latency mode requires High, so the previous Baseline setting is removed.
  If creation rejects the mode, retry with the standard hardware-only encoder.
  No software encoding fallback. H.264 hardware is still required.
- Keep one admitted frame until receiver pipe-write ACK; do not add a frame queue.
- NM02 adds separate diagnostic durations. The Windows 0.1.3 reader accepts
  NM01 too. iOS 0.1.3 REQUIRES Windows 0.1.3; old receivers reject NM02.
- Existing bounded encoder recovery remains in place.

## Packet and measurements

Network byte order; header: `!4sIQQQ` (32 bytes). NM01 payload follows immediately.
NM02 has an additional `!7Q` (56 bytes) before the payload. Payload length excludes
both headers and remains bounded at 8 MiB. The seven fields, in order:

1. queue_us: admission to entry into the encoding queue.
2. prepare_us: queue entry to just before the encode call; includes setup on
   first frames and resizing/CI render submission. GPU work may complete later.
3. callback_queue_us: callback entry to handling it on the encoding queue.
4. previous_ack_us: PREVIOUS sent frame's send scheduling through ACK callback;
   includes USB and receiver pipe backpressure, not transport alone or display.
   First frame reports zero; this is not a current-frame RTT measurement.
5. source_work_us: admission to encoded-frame handling; excludes capture time
   before admission, packet serialization, USB, decoding and display.
6. app_state: state at admission: 0 active, 1 inactive (e.g. notification UI),
   2 background. A frame may cross a state transition.
7. thermal_state: OS thermal state at packet assembly: 0 nominal, 1 fair,
   2 serious, 3 critical. This is not a temperature in degrees.

Base-header encoder_us in NM02: encode call preparation to callback entry.
This still includes OS scheduling until the callback runs, not isolated chip time.
NM01 retains its original meaning. Never subtract Windows and iPhone clocks.
Console shows per-window maximum durations, not only the last sample. Maxima
can belong to different frames and must not be added. CSV preserves each frame.
Only transmitted frames have diagnostic records. No received frames means no
new diagnostics; the app's encoder error text remains relevant in that case.

## Required device comparison

Install both 0.1.3 components. Keep existing iproxy/mpv and Apple drivers.
Record 10 seconds inside the app, 10 seconds with notifications open and moving,
then 30 seconds in a game with continuous motion. Send the CSV (or the console
with the new timing lines) and any iPhone error. Static screens may legitimately
produce fewer frames; use motion in each segment. Compare with the supplied
0.1.2 results, record exact iOS version/game and whether the phone is hot.

Film iPhone and monitor together with another camera to measure visible delay;
internal timings do not replace that measurement. Background fluency, rotation,
actual D3D11VA use and a stable playable session remain unverified for 0.1.3.

## Primary references

- https://developer.apple.com/documentation/videotoolbox/encoding-video-for-low-latency-conferencing
- https://developer.apple.com/documentation/videotoolbox/kvtvideoencoderspecification_enablelowlatencyratecontrol
- https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_prioritizeencodingspeedoverquality
- https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/minimumframeinterval
- https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth
