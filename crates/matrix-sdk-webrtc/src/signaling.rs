//! Matrix `m.call.*` signaling layer.
//!
//! Implements the client-side of
//! [MSC3401](https://github.com/matrix-org/matrix-spec-proposals/pull/3401)
//! (MatrixRTC). Responsible for:
//!
//! - Sending / receiving `m.call.invite`, `m.call.answer`, `m.call.candidates`,
//!   `m.call.hangup`, and related events.
//! - Mapping Matrix room members to WebRTC peer connections.
//! - Negotiating call intents (audio / video) via MatrixRTC member events.

use std::collections::HashMap;
use std::sync::Arc;

use crate::CallType;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Unique identifier for a call session within a Matrix room.
///
/// Typically a Matrix event ID or a custom UUID.
pub type CallId = String;

/// A Matrix call signaling event.
///
/// These correspond to the standard `m.call.*` Matrix event types
/// defined in MSC3401 and related proposals.
#[derive(Debug, Clone)]
/// A Matrix `m.call.*` event, parsed into a structured enum.
///
/// Variants correspond to the standard MSC3401 / WebRTC call
/// signalling lifecycle: Invite → Answer ↔ IceCandidates →
/// Hangup.
///
/// Callers typically don't construct these directly; they are
/// produced by `MatrixCallTransport` or fed into
/// `CallManager::on_signaling_event`.
pub enum CallEvent {
    /// Outgoing or incoming call invitation (`m.call.invite`).
    Invite {
        /// Unique call identifier.
        call_id: CallId,
        /// SDP offer / answer body.
        sdp: String,
        /// Call type negotiated for this call.
        call_type: CallType,
    },
    /// Answer to a call invitation (`m.call.answer`).
    Answer {
        call_id: CallId,
        sdp: String,
    },
    /// Batch of ICE candidates (`m.call.candidates`).
    IceCandidates {
        call_id: CallId,
        /// Candidate strings in SDP format (e.g. `candidate:...`).
        candidates: Vec<String>,
    },
    /// Call termination (`m.call.hangup`).
    Hangup {
        call_id: CallId,
        /// Optional human-readable reason.
        reason: Option<String>,
    },
}

/// Trait that abstracts the actual Matrix event transport.
///
/// Upstream crates (e.g. `matrix-sdk`) implement this trait to bridge
/// between [`SignalingManager`] and the real Matrix room event stream.
///
/// TODO(step-2): wire this into `matrix-sdk`'s timeline event handling.
/// Abstraction over the transport layer used to send call signalling.
///
/// Implementations must be `Send + Sync` so they can be shared across
/// tasks.  The default implementation is `MatrixCallTransport`,
/// which sends `m.call.*` events over Matrix rooms.
///
/// To use a non-Matrix transport (e.g. XMPP Jingle), implement this
/// trait and pass the instance to
/// `CallManager::set_transport`.
pub trait SignalingTransport: Send + Sync {
    /// Send a [`CallEvent`] to the remote peer(s) via Matrix.
    fn send(&self, event: CallEvent);
}

// ---------------------------------------------------------------------------
// SignalingManager
// ---------------------------------------------------------------------------

/// Manages the MatrixRTC signaling lifecycle for a set of calls.
///
/// Each registered call is identified by a [`CallId`] and is associated with
/// a string handle that the caller can use to look up the underlying
/// [`PeerConnection`](crate::connection::PeerConnection) in a separate
/// registry (or, in future steps, stored directly when the `webrtc` feature
/// is active).
/// Internal registry that tracks active calls and their users.
///
/// The manager is **not** part of the public API – it is consumed
/// internally by `CallManager`.  It stores the mapping from
/// `call_id` to the Matrix user ID of the callee (or caller) and
/// exposes helpers for registration, lookup, and event validation.
pub struct SignalingManager {
    /// Transport for sending outbound Matrix events.
    ///
    /// `None` means the transport has not been set yet; `send_event` will
    /// return an error until one is configured.
    transport: Option<Arc<dyn SignalingTransport>>,

    /// Active calls, keyed by [`CallId`].
    ///
    /// The value is an opaque handle string provided by the caller at
    /// registration time.  The caller is responsible for mapping this
    /// handle back to a concrete [`PeerConnection`].
    calls: HashMap<CallId, String>,
}

impl SignalingManager {
    /// Create a new, empty [`SignalingManager`] without a transport.
    ///
    /// Call [`set_transport`](Self::set_transport) before sending events.
    pub fn new() -> Self {
        Self {
            transport: None,
            calls: HashMap::new(),
        }
    }

    /// Set or replace the Matrix event transport.
    pub fn set_transport(
        &mut self,
        transport: Box<dyn SignalingTransport>,
    ) {
        self.transport = Some(Arc::from(transport));
    }

    /// Register a peer connection handle for an active call.
    ///
    /// `handle` is an opaque identifier that the caller uses to retrieve
    /// the corresponding [`PeerConnection`] when processing incoming
    /// signaling events.
    pub fn register_call(&mut self, call_id: CallId, handle: String) {
        self.calls.insert(call_id, handle);
    }

    /// Unregister a call (e.g. after hangup).
    ///
    /// Returns the previously-registered handle, if any.
    pub fn unregister_call(&mut self, call_id: &str) -> Option<String> {
        self.calls.remove(call_id)
    }

    /// Send a [`CallEvent`] through the configured transport.
    ///
    /// Returns an error if no transport has been set.
    pub fn send_event(&self, event: CallEvent) -> Result<(), SignalingError> {
        match &self.transport {
            Some(t) => {
                t.send(event);
                Ok(())
            }
            None => Err(SignalingError::NoTransport),
        }
    }

    /// Handle an incoming [`CallEvent`] received from the Matrix room.
    ///
    /// Returns the handle string registered for this call so the caller
    /// can route the event to the correct [`PeerConnection`].
    ///
    /// If the event refers to an unknown [`CallId`], returns `Ok(None)` —
    /// it is the caller's responsibility to decide whether to create a
    /// new call or drop the event.
    pub fn on_event_received(
        &self,
        event: &CallEvent,
    ) -> Result<Option<&str>, SignalingError> {
        let call_id = match event {
            CallEvent::Invite { call_id, .. }
            | CallEvent::Answer { call_id, .. }
            | CallEvent::IceCandidates { call_id, .. }
            | CallEvent::Hangup { call_id, .. } => call_id,
        };

        Ok(self.calls.get(call_id).map(String::as_str))
    }

    /// Number of currently active (registered) calls.
    pub fn call_count(&self) -> usize {
        self.calls.len()
    }

    /// Check whether a specific `call_id` is currently registered.
    pub fn is_call_registered(&self, call_id: &str) -> bool {
        self.calls.contains_key(call_id)
    }

    /// Return a clone of the current transport, if set.
    ///
    /// Used by `CallManager`(crate::CallManager) to spawn background
    /// signaling drain tasks.
    pub fn transport(&self) -> Option<Arc<dyn SignalingTransport>> {
        self.transport.clone()
    }
}

impl Default for SignalingManager {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Errors specific to the signaling layer.
#[derive(Debug, thiserror::Error)]
pub enum SignalingError {
    /// No transport has been configured yet.
    #[error("no signaling transport configured")]
    NoTransport,
}


