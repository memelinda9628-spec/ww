//! Error types for the WebRTC call engine.

/// Top-level error enum for matrix-sdk-webrtc operations.
#[derive(Debug, thiserror::Error)]
/// Unified error type for all WebRTC call operations.
///
/// Every public method in the crate returns `Result<T, CallError>`.
pub enum CallError {
    /// A signaling-related error occurred (e.g. invalid `m.call.*` event).
    #[error("signaling error: {0}")]
    Signaling(String),

    /// An ICE / peer-connection error occurred at the transport layer.
    #[error("connection error: {0}")]
    Connection(String),

    /// A media (audio/video) track error occurred.
    #[error("media error: {0}")]
    Media(String),

    /// A mesh-topology error (e.g. participant limit exceeded).
    #[error("mesh error: {0}")]
    Mesh(String),

    /// An invalid configuration was supplied.
    #[error("invalid configuration: {0}")]
    Config(String),

    /// A call management error occurred.
    #[error("call error: {0}")]
    Call(String),
}
