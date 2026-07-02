//! matrix-sdk-webrtc — Pure Rust P2P WebRTC call engine.
//!
//! This crate provides a WebRTC-based voice/video calling engine built on top
//! of [matrix-rust-sdk]. It supports 1:1 peer-to-peer calls and small-group
//! (up to 6 participants) full-mesh conferencing.
//!
//! Signaling is exchanged via Matrix `m.call.*` standard events
//! ([MSC3401](https://github.com/matrix-org/matrix-spec-proposals/pull/3401)
//! and friends).
//!
//! # Quick start
//!
//! ```ignore
//! use matrix_sdk_webrtc::{CallConfig, CallType};
//!
//! let config = CallConfig::default();
//! let call_type = CallType::Video;
//! ```
//!
//! # Feature flags
//!
//! | Flag     | Description                          |
//! |----------|--------------------------------------|
//! | `uniffi` | Enable UniFFI-based FFI scaffolding. |

#![doc(html_logo_url = "https://matrix.org/images/matrix-logo.svg")]
#![doc(html_favicon_url = "https://matrix.org/favicon.ico")]

pub mod call;
pub mod config;
pub mod connection;
pub mod error;
pub mod media;
pub mod mesh;
pub mod signaling;
pub mod transport;

mod sealed;

#[cfg(feature = "webrtc")]
pub use call::CallManager;
#[cfg(feature = "webrtc")]
pub use call::ensure_crypto_provider;
pub use config::CallConfig;
pub use connection::PeerConnectionState;
pub use error::CallError;
pub use mesh::{MeshError, MeshTopology};
pub use signaling::{
    CallEvent, CallId, SignalingError, SignalingManager,
    SignalingTransport,
};
pub use transport::MatrixCallTransport;
pub use media::VideoCodec;

/// The type of a WebRTC call.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CallType {
    /// Audio-only call.
    Audio,
    /// Video call (with audio).
    Video,
    /// Call that starts with both audio and video.
    AudioVideo,
}
