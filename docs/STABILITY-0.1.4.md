# 0.1.4 — CPU scaling and persistent receiver

## Evidence from the 0.1.3 device test

The supplied trace reports thermal state serious throughout. In background,
image preparation reached 1003 ms, encoder-to-callback 533.5 ms and admitted
source work 1544.6 ms. USB+ACK was usually single-digit or low tens of ms after
connection warmup. This identifies slow source work but does not establish a
single root cause or a process crash. Core Image render submission, scheduling,
thermal throttling and capture/encoder behavior remain distinct possibilities.

The old receiver deliberately destroyed mpv on its five-second socket timeout.
Its watchdog also timed lack of incoming video as if it were a blocked pipe.
These explain window closures without implying that the iPhone app crashed.

## Changes

- Remove Core Image from the pipeline. Resize BGRA or NV12 (full/video range)
  with CPU-only Accelerate/vImage. Preserve row stride, channel order and pixel
  buffer attachments. Unsupported formats fail explicitly; no hidden GPU fallback.
- Keep hardware H.264, low-latency mode and bounded recovery from 0.1.3.
- Thermal target: normally within 1280×720 at up to 60 FPS; serious heat reduces
  to 960×540 / 30 FPS; critical heat to 960×540 / 15 FPS. Aspect ratio is preserved.
  Restore the normal target only after 30 seconds below serious heat.
  These are ceilings, not measured capture/display rates. Intentional admission
  drops still contribute to source_frames_skipped. Reduced quality is temporary.
- Keep mpv and its stdin open across USB pauses/reconnections. A one-second socket
  idle check preserves partial headers and payloads. At 30 seconds without a
  complete frame, reconnect USB while preserving the existing player/window.
- Watchdog only measures an actual blocked pipe write, not absence of new video.
  A blocked decoder may still be terminated/restarted, bounded to three retries.
  Explicit mpv exit is reported and honored. Final cleanup stops child processes.
- NM02 and CSV fields remain unchanged; the 0.1.4 EXE also reads older NM01 IPAs.

## Automated checks

Python: fragmented NM01/NM02, EOF/limits, ACK, mpv args, idle timeouts across partial
frames, 30-second reconnect deadline, user exit, active-write-only watchdog and
reusing a live child process across starts/writes.

Xcode runner: native vImage tests for BGRA and both NV12 ranges, portrait and
landscape dimensions, padded strides, channel preservation, invalid format
rejection, thermal transitions/hysteresis; existing encoder recovery tests.
Full unsigned iOS device build and packaged Windows EXE --help smoke test.

These checks do not prove background stability on the user's iPhone.

## Next physical test

Install IPA and replace Windows EXE, retaining iproxy/mpv/dependencies. Start with
the phone cooled and record a moving scene in-app, notification UI and a game.
Send console/CSV including thermal state and image preparation durations.
If a closure persists, distinguish Windows video window, Windows console or
actual iPhone app exit. For an actual iPhone exit, obtain its crash/jetsam report;
these console logs alone cannot identify the termination reason.

Sources: Apple background GPU restrictions and CPU image scaling:
https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background
https://developer.apple.com/documentation/accelerate/image-scaling
