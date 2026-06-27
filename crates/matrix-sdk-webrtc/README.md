# matrix-sdk-webrtc

Pure Rust P2P WebRTC call engine built on [matrix-rust-sdk] and [webrtc-rs].

Supports 1:1 peer‑to‑peer calls and small‑group full‑mesh conferencing (up to 6 participants). Signalling is exchanged via Matrix  events ([MSC3401] and related proposals).

[MSC3401]: https://github.com/matrix-org/matrix-spec-proposals/pull/3401

---

## Architecture

*(Architecture diagram omitted for brevity)*

---

## Media sharing

Media capture pipelines (microphone, camera) are created **lazily on first use** and then **shared** across all calls and peer connections. Calling  a second time returns the same  without re‑opening the device.

---

## Feature flags

| Flag      | Dependencies                              | Enables                                                               |
|-----------|-------------------------------------------|-----------------------------------------------------------------------|
|   | , , , ,  | Core WebRTC engine — , , signalling drain, data channels |
|    | ,                             | Microphone capture + Opus encoding (implies )                |
|    |                                   | Camera capture (implies )                                   |
|      |                                   | VP8 hardware/software encoding for video (requires )        |
|   |                                   | UniFFI based FFI scaffolding                                          |

You can opt‑out of all heavy dependencies if you only need the signalling types:



---

## Quick start

SignalingTransport

---

## Module overview

| Module       | Purpose |
|--------------|---------|
|        |  — top‑level orchestrator (create, accept, hangup, signalling routing) |
|  |  — wrapper around  for a single peer link |
|   |  — Matrix  event send/receive |
|       |  — local audio/video capture |
|        |  — full‑mesh participant registry |
|      | ,  definitions |
|       | , ,  |

---

## Limitations

- Full‑mesh only (≈6 participants). Larger rooms need an SFU.
- No simulcast / SVC.
- No screen sharing – only microphone and camera.
- Single media pipeline per process.
- UniFFI bindings scaffolded but not wired.

---

## License

Apache‑2.0 (same as [matrix-rust-sdk]).
