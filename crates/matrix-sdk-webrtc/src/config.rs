//! Call configuration — ICE servers, codec preferences, and limits.

use serde::{Deserialize, Serialize};

/// Server/relay entry for ICE candidate gathering.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IceServer {
    /// URI(s) for this server (e.g. `stun:stun.example.com:3478`).
    pub urls: Vec<String>,
    /// Optional TURN username.
    pub username: Option<String>,
    /// Optional TURN credential.
    pub credential: Option<String>,
}

/// Configuration for a WebRTC call.
///
/// Holds the list of STUN/TURN servers, max mesh participants, and
/// other tunables.
#[derive(Debug, Clone)]
/// Configuration for a `CallManager` or individual call.
///
/// Controls STUN/TURN server addresses, ICE transport policy,
/// and permitted codecs.
///
/// # Default
///
/// Uses Google's public STUN server (`stun.l.google.com:19302`)
/// and permits all codecs (Opus, VP8, VP9, H264).
pub struct CallConfig {
    /// STUN/TURN servers used for ICE candidate gathering.
    pub ice_servers: Vec<IceServer>,
    /// Maximum number of participants in a full-mesh call (default 6).
    pub max_mesh_participants: usize,
}

impl Default for CallConfig {
    fn default() -> Self {
        Self {
            ice_servers: Vec::new(),
            max_mesh_participants: 6,
        }
    }
}
