//! CallManager — Top-level orchestrator for WebRTC calls.
//!
//! Owns the signaling layer, mesh topology, media manager, and all active
//! peer connections.  Coordinates outbound call creation, inbound call
//! acceptance, signaling event routing, and hangup.

#[cfg(feature = "webrtc")]
use std::collections::HashMap;
#[cfg(feature = "webrtc")]
use std::sync::Arc;

#[cfg(feature = "webrtc")]
use tokio::sync::mpsc;
#[cfg(feature = "webrtc")]
use tracing::{debug, info};
#[cfg(feature = "webrtc")]
use uuid::Uuid;

#[cfg(feature = "webrtc")]
use webrtc::data_channel::RTCDataChannel;
#[cfg(feature = "webrtc")]
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
#[cfg(feature = "webrtc")]
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;

#[cfg(feature = "webrtc")]
use crate::config::CallConfig;
#[cfg(feature = "webrtc")]
use crate::connection::PeerConnection;
#[cfg(feature = "webrtc")]
use crate::error::CallError;
#[cfg(feature = "webrtc")]
use crate::media::MediaManager;
#[cfg(feature = "webrtc")]
use crate::mesh::MeshTopology;
#[cfg(feature = "webrtc")]
use crate::signaling::{CallEvent, CallId, SignalingManager, SignalingTransport};
#[cfg(feature = "webrtc")]
use crate::CallType;

// ---------------------------------------------------------------------------
// CallManager
// ---------------------------------------------------------------------------

/// Top-level orchestrator for WebRTC calls.
///
/// Owns all sub-components (signaling, mesh, media, peer connections) and
/// provides a single entry-point for creating, accepting, and terminating
/// calls.
///
/// # Lifecycle
///
/// ```text
/// CallManager::new(config)
///   → set_transport(transport)
///   → create_call(...)        // outbound
///   → accept_call(...)        // inbound
///   → on_signaling_event(...)
///   → hangup(...)
/// ```
#[cfg(feature = "webrtc")]
/// Manages the lifecycle of WebRTC peer-to-peer calls.
///
/// `CallManager` is the primary entry point for the crate's public API.
/// It handles call creation, acceptance, signalling event routing,
/// ICE candidate forwarding, and hangup.
///
/// # Example
///
/// ```ignore
/// let mut mgr = CallManager::new(CallConfig::default());
/// mgr.set_transport(Arc::new(transport));
/// let call_id = mgr.create_call("bob", CallType::Video).await?;
/// ```
pub struct CallManager {
    /// Call configuration (ICE servers, codec prefs, limits).
    config: CallConfig,

    /// Matrix signaling layer.
    signaling: SignalingManager,

    /// Full-mesh topology manager.
    mesh: MeshTopology,

    /// Local media capture & track management.
    #[allow(dead_code)]
    media: MediaManager,

    /// Active peer connections.
    ///
    /// Keyed by [`CallId`], each entry maps callee user IDs to their
    /// corresponding [`PeerConnection`] via a `(user_id, Arc<PeerConnection>)` pair.
    connections: HashMap<CallId, Vec<(String, Arc<PeerConnection>)>>,

    pending_invites: HashMap<CallId, (String, CallType)>,
}

#[cfg(feature = "webrtc")]
impl CallManager {
    /// Create a new `CallManager` with the given configuration.
    pub fn new(config: CallConfig) -> Self {
        let max_participants = config.max_mesh_participants;

        Self {
            config,
            signaling: SignalingManager::new(),
            mesh: MeshTopology::new(max_participants),
            media: MediaManager::new(),
            connections: HashMap::new(),
            pending_invites: HashMap::new(),
        }
    }

    /// Check whether a call with the given `call_id` has been registered
    /// in the signaling layer.
    pub fn is_call_registered(&self, call_id: &str) -> bool {
        self.signaling.is_call_registered(call_id)
    }

    /// Set or replace the Matrix event transport.
    pub fn set_transport(
        &mut self,
        transport: Box<dyn SignalingTransport>,
    ) {
        self.signaling.set_transport(transport);
    }

    // ---------------------------------------------------------------
    // Outbound call
    // ---------------------------------------------------------------

    /// Create a new outbound call to the given Matrix user.
    ///
    /// Generates a unique [`CallId`], creates a peer connection, attaches
    /// local media tracks, produces an SDP offer, and sends an
    /// [`CallEvent::Invite`] through the signaling layer.
    pub async fn create_call(
        &mut self,
        callee_user_id: &str,
        call_type: CallType,
    ) -> Result<CallId, CallError> {
        let call_id = Uuid::new_v4().to_string();

        let conn = PeerConnection::new(&self.config).await?;

        conn.on_track(move |track, _receiver| {
            async move {
                info!(
                    "Remote track: kind={}, id={}, stream_id={}",
                    track.kind(),
                    track.id(),
                    track.stream_id()
                );
            }
        });

        let conn = Arc::new(conn);

        // Create local media tracks per call_type (gated by features).
        #[cfg(any(feature = "audio", feature = "video"))]
        match call_type {
            CallType::Audio => {
                #[cfg(feature = "audio")]
                self.media.create_local_audio_track()?;
            }
            CallType::Video | CallType::AudioVideo => {
                #[cfg(feature = "video")]
                self.media.create_local_video_track()?;
                if call_type == CallType::AudioVideo {
                    #[cfg(feature = "audio")]
                    self.media.create_local_audio_track()?;
                }
            }
        }

        #[cfg(any(feature = "audio", feature = "video"))]
        self.media.add_tracks_to_connection(&conn).await?;

        // If the webrtc feature is enabled but media (audio/video) features
        // are NOT, no tracks get added → no m= lines in the SDP → no ICE
        // gathering → ice-ufrag/ice-pwd are missing → remote
        // set_remote_description fails.
        //
        // Create a data channel to add an m=application section, which
        // triggers ICE credential generation.  This mirrors the pattern in
        // the `ice_negotiation_loopback` test.
        #[cfg(not(any(feature = "audio", feature = "video")))]
        {
            let _ = conn.create_data_channel("media-fallback").await;
        }

        let offer = conn.create_offer().await?;

        // Drain ICE candidates from the signaling channel and forward
        // them via the Matrix transport once it arrives.
        if let Some(rx) = conn.take_signaling_receiver() {
            if let Some(transport) = self.signaling.transport() {
                let cid = call_id.clone();
                let _ = tokio::spawn(Self::ice_drain_task(cid, rx, transport));
            }
        }

        self.signaling
            .register_call(call_id.clone(), callee_user_id.to_owned());

        self.mesh
            .add_peer(callee_user_id.to_owned(), callee_user_id.to_owned())
            .map_err(|e| CallError::Mesh(e.to_string()))?;

        self.connections
            .entry(call_id.clone())
            .or_default()
            .push((callee_user_id.to_owned(), conn));

        // Build and send Invite event.
        let event = CallEvent::Invite {
            call_id: call_id.clone(),
            sdp: offer.sdp,
            call_type,
        };
        self.signaling
            .send_event(event)
            .map_err(|e| CallError::Signaling(e.to_string()))?;

        Ok(call_id)
    }

    // ---------------------------------------------------------------
    // Inbound call
    // ---------------------------------------------------------------

    /// Accept an incoming call by creating a peer connection with the
    /// remote offer, attaching local tracks, and sending an SDP answer.
    ///
    /// `caller_user_id` — the Matrix user ID of the remote caller
    /// (extracted from the incoming `m.call.invite` event sender).
    pub async fn accept_call(
        &mut self,
        call_id: CallId,
        caller_user_id: &str,
        offer_sdp: String,
        call_type: CallType,
    ) -> Result<(), CallError> {
        let _ = call_type;
        let offer = RTCSessionDescription::offer(offer_sdp).map_err(|e| {
            CallError::Signaling(format!("invalid remote SDP offer: {e}"))
        })?;

        let conn =
            PeerConnection::new_with_offer(&self.config, offer).await?;

        conn.on_track(move |track, _receiver| {
            async move {
                info!(
                    "Remote track: kind={}, id={}, stream_id={}",
                    track.kind(),
                    track.id(),
                    track.stream_id()
                );
            }
        });

        let conn = Arc::new(conn);

        #[cfg(any(feature = "audio", feature = "video"))]
        match call_type {
            CallType::Audio => {
                #[cfg(feature = "audio")]
                self.media.create_local_audio_track()?;
            }
            CallType::Video | CallType::AudioVideo => {
                #[cfg(feature = "video")]
                self.media.create_local_video_track()?;
                if call_type == CallType::AudioVideo {
                    #[cfg(feature = "audio")]
                    self.media.create_local_audio_track()?;
                }
            }
        }

        #[cfg(any(feature = "audio", feature = "video"))]
        self.media.add_tracks_to_connection(&conn).await?;

        let answer = conn.create_answer().await?;

        // Drain ICE candidates from the signaling channel.
        if let Some(rx) = conn.take_signaling_receiver() {
            if let Some(transport) = self.signaling.transport() {
                let cid = call_id.clone();
                let _ = tokio::spawn(Self::ice_drain_task(cid, rx, transport));
            }
        }

        self.signaling
            .register_call(call_id.clone(), caller_user_id.to_owned());

        self.mesh
            .add_peer(caller_user_id.to_owned(), caller_user_id.to_owned())
            .map_err(|e| CallError::Mesh(e.to_string()))?;

        self.connections
            .entry(call_id.clone())
            .or_default()
            .push((caller_user_id.to_owned(), conn));

        let event = CallEvent::Answer {
            call_id,
            sdp: answer.sdp,
        };
        self.signaling
            .send_event(event)
            .map_err(|e| CallError::Signaling(e.to_string()))?;

        Ok(())
    }

    // ---------------------------------------------------------------
    // Hangup
    // ---------------------------------------------------------------

    /// Terminate a call, cleaning up all associated resources.
    ///
    /// 1. Removes and drops all peer connections (closing PC).
    /// 2. Removes all peers from the mesh.
    /// 3. Unregisters the call from signaling.
    /// 4. Sends a `CallEvent::Hangup` via signaling.
    pub fn poll_pending_invite(&mut self) -> Option<(CallId, String, CallType)> {
        if let Some(key) = self.pending_invites.keys().next().cloned() {
            self.pending_invites.remove(&key).map(|(sdp, ct)| (key, sdp, ct))
        } else {
            None
        }
    }

    pub fn hangup(
        &mut self,
        call_id: &str,
    ) -> Result<(), CallError> {
        if let Some(peers) = self.connections.remove(call_id) {
            for (user_id, _) in &peers {
                self.mesh.remove_peer(user_id);
            }
        }

        self.signaling.unregister_call(call_id);
        self.pending_invites.remove(call_id);

        let _ = self.signaling.send_event(CallEvent::Hangup {
            call_id: call_id.to_owned(),
            reason: None,
        });

        Ok(())
    }

    /// Get the connection state of the first peer connection for the
    /// given call.
    pub fn connection_state(
        &self,
        call_id: &str,
    ) -> Option<crate::connection::PeerConnectionState> {
        self.connections
            .get(call_id)
            .and_then(|peers| peers.first())
            .map(|(_, conn)| conn.connection_state())
    }

    // ---------------------------------------------------------------
    // Data channel
    // ---------------------------------------------------------------

    /// Create a data channel on the first peer connection for the given
    /// call.
    pub async fn create_data_channel(
        &self,
        call_id: &str,
        label: &str,
    ) -> Result<Arc<RTCDataChannel>, CallError> {
        let peers = self
            .connections
            .get(call_id)
            .ok_or_else(|| CallError::Call(format!("call not found: {call_id}")))?;

        let (_, conn) = peers
            .first()
            .ok_or_else(|| CallError::Call(format!("no peer connection for call: {call_id}")))?;

        conn.create_data_channel(label).await
    }

    // ---------------------------------------------------------------
    // Signaling event routing
    // ---------------------------------------------------------------

    /// Handle an incoming [`CallEvent`] received from the Matrix room.
    ///
    /// Routes the event to the correct peer connection based on its type:
    ///
    /// | Event        | Action                                          |
    /// |--------------|-------------------------------------------------|
    /// | `Invite`     | Logged at debug level only.                     |
    /// | `Answer`     | `set_remote_description` on the peer connection.|
    /// | `IceCandidates` | `add_ice_candidate` for each candidate.       |
    /// | `Hangup`     | Calls [`hangup`](Self::hangup).                 |
    pub async fn on_signaling_event(
        &mut self,
        event: &CallEvent,
    ) -> Result<(), CallError> {
        match event {
            CallEvent::Invite { call_id, sdp, call_type } => {
                debug!(
                    "Received Invite for call {} — storing as pending",
                    call_id
                );
                self.pending_invites.insert(call_id.clone(), (sdp.clone(), *call_type));
            }
            CallEvent::Answer { call_id, sdp } => {
                let sdp = RTCSessionDescription::answer(sdp.clone()).map_err(
                    |e| {
                        CallError::Signaling(format!(
                            "invalid remote SDP answer: {e}"
                        ))
                    },
                )?;

                if let Some(peers) = self.connections.get(call_id) {
                    for (_, conn) in peers {
                        conn.set_remote_description(sdp.clone()).await?;
                    }
                }
            }
            CallEvent::IceCandidates {
                call_id,
                candidates,
            } => {
                if let Some(peers) = self.connections.get(call_id) {
                    for candidate_str in candidates {
                        let init = RTCIceCandidateInit {
                            candidate: candidate_str.clone(),
                            ..Default::default()
                        };

                        for (_, conn) in peers {
                            conn.add_ice_candidate_init(init.clone()).await?;
                        }
                    }
                }
            }
            CallEvent::Hangup { call_id, .. } => {
                return self.hangup(call_id);
            }
        }

        Ok(())
    }

    // ---------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------

    /// Background task that drains the signaling `mpsc` channel for a
    /// single peer connection, forwarding any ICE candidates to the
    /// Matrix transport.
    async fn ice_drain_task(
        call_id: String,
        mut rx: mpsc::Receiver<crate::connection::SignalingMessage>,
        transport: Arc<dyn SignalingTransport>,
    ) {
        use crate::connection::SignalingMessage as SigMsg;
        while let Some(msg) = rx.recv().await {
            if let SigMsg::IceCandidate(c) = msg {
                if let Ok(init) = c.to_json() {
                    let event = CallEvent::IceCandidates {
                        call_id: call_id.clone(),
                        candidates: vec![init.candidate],
                    };
                    transport.send(event);
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Crypto provider bootstrap
// ---------------------------------------------------------------------------

/// Install the rustls crypto provider (required by webrtc-rs for DTLS).
///
/// Idempotent – calling multiple times across multiple crates is safe.
#[cfg(feature = "webrtc")]
pub fn ensure_crypto_provider() {
    use std::sync::Once;
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        rustls::crypto::ring::default_provider()
            .install_default()
            .expect("failed to install rustls ring crypto provider");
    });
}

// ---------------------------------------------------------------------------
// End-to-end P2P tests
// ---------------------------------------------------------------------------

#[cfg(all(test, feature = "webrtc"))]
mod tests {
    use super::*;
    use std::sync::Mutex as StdMutex;
    use std::time::Duration;
    use tokio::sync::mpsc;
    use crate::connection::{PeerConnection, PeerConnectionState, SignalingMessage};

    /// A bidirectional loopback transport that bridges two
    /// `CallManager` instances for end-to-end testing.
    struct LoopbackTransport {
        /// Identifier for debugging.
        name: String,
        /// Incoming events from the peer transport.
        rx: StdMutex<Option<mpsc::UnboundedReceiver<CallEvent>>>,
        /// Outbound sender that the peer will read from.
        tx: mpsc::UnboundedSender<CallEvent>,
    }

    impl LoopbackTransport {
        /// Create a linked pair `(alice, bob)` such that events sent
        /// via `alice` arrive at `bob`, and vice versa.
        fn pair() -> (Self, Self) {
            let (tx_a, rx_b) = mpsc::unbounded_channel(); // Alice → Bob
            let (tx_b, rx_a) = mpsc::unbounded_channel(); // Bob → Alice

            let alice = Self {
                name: "alice".into(),
                rx: StdMutex::new(Some(rx_a)),
                tx: tx_a, // Alice sends to Bob
            };
            let bob = Self {
                name: "bob".into(),
                rx: StdMutex::new(Some(rx_b)),
                tx: tx_b, // Bob sends to Alice
            };
            (alice, bob)
        }

        /// Take ownership of the receiver channel (used once during setup).
        fn take_rx(&self) -> mpsc::UnboundedReceiver<CallEvent> {
            self.rx.lock().unwrap().take().unwrap()
        }
    }

    impl SignalingTransport for LoopbackTransport {
        fn send(&self, event: CallEvent) {
            debug!("{} sending {:?}", self.name, event);
            let _ = self.tx.send(event);
        }
    }

    /// Background task: drain the loopback receiver and forward each
    /// event to the other `CallManager`'s `on_signaling_event`.
    async fn relay_task(
        who: &'static str,
        mut rx: mpsc::UnboundedReceiver<CallEvent>,
        cm: Arc<tokio::sync::Mutex<CallManager>>,
    ) {
        while let Some(event) = rx.recv().await {
            debug!("{who} received {:?}", event);
            let mut guard = cm.lock().await;
            if let Err(e) = guard.on_signaling_event(&event).await {
                debug!("{who} on_signaling_event error: {e}");
            }
        }
    }

    // ---------------------------------------------------------------
    // Test: Signaling round-trip via loopback transport
    // ---------------------------------------------------------------
    ///
    /// Verifies that CallEvent messages are correctly sent and
    /// received bidirectionally through the transport layer without
    /// requiring actual WebRTC media negotiation.

    #[tokio::test]
    async fn signaling_loopback() {
        let config = CallConfig::default();

        // ---- Setup two CallManagers ----

        let (t_a, t_b) = LoopbackTransport::pair();
        let rx_b = t_b.take_rx();
        let rx_a = t_a.take_rx(); // events from B → A

        let mut alice = CallManager::new(config.clone());
        alice.set_transport(Box::new(t_a));

        let mut bob = CallManager::new(config.clone());
        bob.set_transport(Box::new(t_b));

        let alice = Arc::new(tokio::sync::Mutex::new(alice));
        let bob = Arc::new(tokio::sync::Mutex::new(bob));

        // Relay tasks: forward events between Alice and Bob.
        let relay_a2b = tokio::spawn(relay_task("bob", rx_b, bob.clone()));
        let relay_b2a = tokio::spawn(relay_task("alice", rx_a, alice.clone()));

        let call_id = Uuid::new_v4().to_string();
        let alice_user = "@alice:matrix.org";
        let bob_user = "@bob:matrix.org";

        // ---- Alice sends an Invite to Bob ----

        {
            let mut a = alice.lock().await;
            a.signaling
                .register_call(call_id.clone(), bob_user.to_owned());
            a.mesh
                .add_peer(bob_user.to_owned(), bob_user.to_owned())
                .unwrap();
            a.signaling
                .send_event(CallEvent::Invite {
                    call_id: call_id.clone(),
                    sdp: "v=0\no=- 0 0 IN IP4 127.0.0.1".into(),
                    call_type: CallType::Audio,
                })
                .unwrap();
        }

        tokio::time::sleep(Duration::from_millis(200)).await;

        // Bob received the invite but should NOT auto-register
        // (on_signaling_event for Invite only logs, doesn't register).
        {
            let b = bob.lock().await;
            assert!(
                !b.signaling.is_call_registered(&call_id),
                "Bob should not auto-register on invite (accept_call does that)"
            );
        }

        // ---- Bob accepts: registers call + sends Answer ----

        {
            let mut b = bob.lock().await;
            b.signaling
                .register_call(call_id.clone(), alice_user.to_owned());
            b.mesh
                .add_peer(alice_user.to_owned(), alice_user.to_owned())
                .unwrap();
            b.signaling
                .send_event(CallEvent::Answer {
                    call_id: call_id.clone(),
                    sdp: "v=0\no=- 0 0 IN IP4 127.0.0.2".into(),
                })
                .unwrap();
        }

        tokio::time::sleep(Duration::from_millis(200)).await;

        // Both sides should now have the call registered.
        {
            let a = alice.lock().await;
            let b = bob.lock().await;
            assert!(a.signaling.is_call_registered(&call_id));
            assert!(b.signaling.is_call_registered(&call_id));
        }

        // ---- Bob sends ICE candidates ----

        {
            let b = bob.lock().await;
            b.signaling
                .send_event(CallEvent::IceCandidates {
                    call_id: call_id.clone(),
                    candidates: vec![
                        "candidate:1 1 UDP 2122252543 192.168.1.1 12345 typ host"
                            .into(),
                    ],
                })
                .unwrap();
        }

        tokio::time::sleep(Duration::from_millis(200)).await;

        // ---- Alice sends ICE candidates back ----

        {
            let a = alice.lock().await;
            a.signaling
                .send_event(CallEvent::IceCandidates {
                    call_id: call_id.clone(),
                    candidates: vec![
                        "candidate:2 1 UDP 2122252543 10.0.0.1 23456 typ host"
                            .into(),
                    ],
                })
                .unwrap();
        }

        tokio::time::sleep(Duration::from_millis(200)).await;

        // ---- Alice hangs up ----

        {
            let a = alice.lock().await;
            a.signaling
                .send_event(CallEvent::Hangup {
                    call_id: call_id.clone(),
                    reason: Some("done".into()),
                })
                .unwrap();
        }

        tokio::time::sleep(Duration::from_millis(200)).await;

        // Bob should have removed the call after receiving hangup.
        {
            let b = bob.lock().await;
            assert!(
                !b.signaling.is_call_registered(&call_id),
                "Bob should have unregistered the call after hangup"
            );
        }

        relay_a2b.abort();
        relay_b2a.abort();
    }

    // ---------------------------------------------------------------
    // Test: hangup() method integration
    // ---------------------------------------------------------------

    /// Verifies that calling [`CallManager::hangup`] produces the
    /// expected local side-effects and that the remote peer receives
    /// the Hangup event through the signaling transport, triggering
    /// its own cleanup.
    #[tokio::test]
    async fn hangup_integration() {
        let config = CallConfig::default();

        let (t_a, t_b) = LoopbackTransport::pair();
        let rx_b = t_b.take_rx();

        let mut alice = CallManager::new(config.clone());
        alice.set_transport(Box::new(t_a));

        let mut bob = CallManager::new(config.clone());
        bob.set_transport(Box::new(t_b));

        let alice = Arc::new(tokio::sync::Mutex::new(alice));
        let bob = Arc::new(tokio::sync::Mutex::new(bob));

        let relay = tokio::spawn(relay_task("bob", rx_b, bob.clone()));

        let call_id = Uuid::new_v4().to_string();
        let alice_user = "@alice:matrix.org";
        let bob_user = "@bob:matrix.org";

        // Simulate post-create_call / post-accept_call state.
        {
            let mut a = alice.lock().await;
            a.signaling.register_call(call_id.clone(), bob_user.to_owned());
            a.mesh.add_peer(bob_user.to_owned(), bob_user.to_owned()).unwrap();

            let mut b = bob.lock().await;
            b.signaling.register_call(call_id.clone(), alice_user.to_owned());
            b.mesh.add_peer(alice_user.to_owned(), alice_user.to_owned()).unwrap();
        }

        // Alice initiates hangup via the public method.
        {
            let mut a = alice.lock().await;
            a.hangup(&call_id).unwrap();
        }

        tokio::time::sleep(Duration::from_millis(300)).await;

        // Alice should have unregistered locally.
        {
            let a = alice.lock().await;
            assert!(
                !a.signaling.is_call_registered(&call_id),
                "Alice should unregister after hangup()"
            );
        }

        // Bob should have received the Hangup event and cleaned up.
        {
            let b = bob.lock().await;
            assert!(
                !b.signaling.is_call_registered(&call_id),
                "Bob should unregister after receiving Hangup from Alice"
            );
        }

        relay.abort();

        // Give RTP packets time to flow after ICE/DTLS completes
        tokio::time::sleep(Duration::from_millis(500)).await;
    }

    // ---------------------------------------------------------------
    // Test: ICE negotiation with real webrtc-rs PeerConnections
    // ---------------------------------------------------------------

    /// Creates two [`PeerConnection`] instances, exchanges SDP and ICE
    /// candidates via in-process channels, and verifies that both reach
    /// the `Connected` state — a true end-to-end ICE negotiation test.
    ///
    /// Follows the webrtc-rs `signal_pair` pattern: create a data channel
    /// first to trigger ICE initialisation, then exchange SDP and ICE
    /// candidates.
    #[tokio::test]
    async fn ice_negotiation_loopback() {
        ensure_crypto_provider();
        let config = CallConfig::default();

        // ---- Create two PeerConnections + data channel (triggers ICE) ----

        let alice_pc = PeerConnection::new(&config).await.unwrap();
        let bob_pc = PeerConnection::new(&config).await.unwrap();

        // Create a data channel to trigger ICE initialisation (ufrag/pwd).
        // This mirrors the webrtc-rs signal_pair pattern:
        //   pc_offer.create_data_channel("initial_data_channel", None)
        alice_pc.create_data_channel("loopback").await.unwrap();
        bob_pc.create_data_channel("loopback").await.unwrap();

        let mut alice_rx = alice_pc.take_signaling_receiver().unwrap();
        let mut bob_rx = bob_pc.take_signaling_receiver().unwrap();

        // ---- SDP exchange ----

        let offer = alice_pc.create_offer().await.unwrap();

        bob_pc.set_remote_description(offer).await.unwrap();
        let answer = bob_pc.create_answer().await.unwrap();

        let alice = Arc::new(alice_pc);
        let bob = Arc::new(bob_pc);

        eprintln!("[DEBUG] Alice set remote desc...");
        alice.set_remote_description(answer).await.unwrap();

        // ---- ICE candidate relay (bi-directional) ----

        let alice_for_relay = alice.clone();
        let bob_for_relay = bob.clone();

        let relay = tokio::spawn(async move {
            loop {
                tokio::select! {
                    // Alice → Bob
                    maybe_msg = alice_rx.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(c)) => {
                                let _ = bob_for_relay.add_ice_candidate(c).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                    // Bob → Alice
                    maybe_msg = bob_rx.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(c)) => {
                                let _ = alice_for_relay.add_ice_candidate(c).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                }
            }
        });

        // ---- Wait for both sides to reach Connected ----

        eprintln!("[DEBUG] Starting ICE wait loop");
        let deadline = tokio::time::Instant::now() + Duration::from_secs(10);

        loop {
            let alice_state = alice.connection_state();
            let bob_state = bob.connection_state();

            if alice_state == PeerConnectionState::Connected
                && bob_state == PeerConnectionState::Connected
            {
                break;
            }

            if tokio::time::Instant::now() > deadline {
                relay.abort();
                panic!(
                    "ICE negotiation timed out after 10s: \
                     alice={alice_state:?} bob={bob_state:?}"
                );
            }

            eprintln!("[DEBUG] ICE: alice={alice_state:?} bob={bob_state:?}");
            tokio::time::sleep(Duration::from_millis(50)).await;
        }

        relay.abort();

        // Give RTP packets time to flow after ICE/DTLS completes
        tokio::time::sleep(Duration::from_millis(500)).await;

        assert_eq!(
            alice.connection_state(),
            PeerConnectionState::Connected,
            "Alice should be Connected"
        );
        assert_eq!(
            bob.connection_state(),
            PeerConnectionState::Connected,
            "Bob should be Connected"
        );
    }

    // ---------------------------------------------------------------
    // Test: media track loopback via external tracks
    // ---------------------------------------------------------------

    /// Injects external audio/video tracks via [`MediaManager`], runs a
    /// full SDP+ICE exchange between two [`PeerConnection`]s, and verifies
    /// that the remote side receives the tracks through the `on_track`
    /// callback with correct kind and stream metadata.
    #[tokio::test]
    async fn media_track_loopback() {
        use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
        use webrtc::track::track_local::TrackLocal;
        use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
        use webrtc::media::Sample;
        use crate::media::MediaManager;

        ensure_crypto_provider();
        let config = CallConfig::default();

        // ---- Mock external tracks (no real devices) ----

        let audio_sample_track = Arc::new(
            TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: "audio/opus".to_owned(),
                    clock_rate: 48000,
                    channels: 2,
                    ..Default::default()
                },
                "audio".to_owned(),
                "test-audio".to_owned(),
            ),
        );
        let audio_track: Arc<dyn TrackLocal + Send + Sync> = audio_sample_track.clone();

        let video_sample_track = Arc::new(
            TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: "video/VP8".to_owned(),
                    clock_rate: 90000,
                    ..Default::default()
                },
                "video".to_owned(),
                "test-video".to_owned(),
            ),
        );
        let video_track: Arc<dyn TrackLocal + Send + Sync> = video_sample_track.clone();

        let mut alice_media = MediaManager::new();
        alice_media.set_audio_track(audio_track);
        alice_media.set_video_track(video_track);

        // ---- Alice creates PC with media tracks ----

        let alice_pc = PeerConnection::new(&config).await.unwrap();
        alice_pc.create_data_channel("loopback").await.unwrap();
        alice_media
            .add_tracks_to_connection(&alice_pc)
            .await
            .unwrap();

        let mut alice_rx = alice_pc.take_signaling_receiver().unwrap();
        let alice = Arc::new(alice_pc);

        // ---- Bob creates PC with on_track callback ----

        let bob_pc = PeerConnection::new(&config).await.unwrap();
        bob_pc.create_data_channel("loopback").await.unwrap();
        let (track_tx, mut track_rx) =
            tokio::sync::mpsc::channel::<String>(8);

        bob_pc.on_track(move |track, _receiver| {
            let tx = track_tx.clone();
            async move {
                let _ = tx
                    .send(format!(
                        "{}:{}",
                        track.kind(),
                        track.stream_id()
                    ))
                    .await;
            }
        });

        let mut bob_rx = bob_pc.take_signaling_receiver().unwrap();
        let bob = Arc::new(bob_pc);

        // ---- ICE candidate relay (bi-directional) ----

        let alice_for_relay = alice.clone();
        let bob_for_relay = bob.clone();

        let relay = tokio::spawn(async move {
            loop {
                tokio::select! {
                    maybe_msg = alice_rx.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(c)) => {
                                let _ = bob_for_relay.add_ice_candidate(c).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                    maybe_msg = bob_rx.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(c)) => {
                                let _ = alice_for_relay.add_ice_candidate(c).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                }
            }
        });

        // ---- SDP exchange ----

        let offer = alice.create_offer().await.unwrap();
        bob.set_remote_description(offer).await.unwrap();
        let answer = bob.create_answer().await.unwrap();
        alice.set_remote_description(answer).await.unwrap();

        // After negotiation, bind() has been called, so the packetizer is ready.
        // Continuously write samples so RTP packets flow to Bob.
        let writer_audio = audio_sample_track.clone();
        let writer_video = video_sample_track.clone();
        let _writer = tokio::spawn(async move {
            loop {
                let ts = std::time::SystemTime::now();
                let _ = writer_audio.write_sample(&Sample {
                    data: bytes::Bytes::from(vec![0u8; 960]),
                    duration: Duration::from_millis(20),
                    timestamp: ts,
                    ..Default::default()
                }).await;
                let _ = writer_video.write_sample(&Sample {
                    data: bytes::Bytes::from(vec![0u8; 100]),
                    duration: Duration::from_millis(33),
                    timestamp: ts,
                    ..Default::default()
                }).await;
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        });

        // ---- Wait for Connected ----

        let deadline =
            tokio::time::Instant::now() + Duration::from_secs(15);

        loop {
            let alice_state = alice.connection_state();
            let bob_state = bob.connection_state();

            if alice_state == PeerConnectionState::Connected
                && bob_state == PeerConnectionState::Connected
            {
                break;
            }

            if tokio::time::Instant::now() > deadline {
                relay.abort();
                panic!(
                    "ICE negotiation timed out after 15s: alice={alice_state:?} bob={bob_state:?}"
                );
            }

            tokio::time::sleep(Duration::from_millis(50)).await;
        }

        relay.abort();

        // Give RTP packets time to flow after ICE/DTLS completes
        tokio::time::sleep(Duration::from_millis(500)).await;

        // ---- Verify connection state ----

        assert_eq!(
            alice.connection_state(),
            PeerConnectionState::Connected,
            "Alice should be Connected"
        );
        assert_eq!(
            bob.connection_state(),
            PeerConnectionState::Connected,
            "Bob should be Connected"
        );

        // ---- Verify remote tracks received (drain channel) ----

        let mut received = Vec::new();
        while let Ok(kind) = track_rx.try_recv() {
            received.push(kind);
        }

        assert!(
            !received.is_empty(),
            "Bob should have received at least one remote track"
        );

        let audio_count = received
            .iter()
            .filter(|s| s.starts_with("audio"))
            .count();
        let video_count = received
            .iter()
            .filter(|s| s.starts_with("video"))
            .count();

        assert!(
            audio_count >= 1,
            "Expected at least 1 audio track, got {} (received: {:?})",
            audio_count,
            received
        );
        assert!(
            video_count >= 1,
            "Expected at least 1 video track, got {} (received: {:?})",
            video_count,
            received
        );
    }


    // ---------------------------------------------------------------
    // Test: real device loopback
    // ---------------------------------------------------------------

    /// Opens the real microphone and camera (when available), injects
    /// their tracks via [`MediaManager`], runs a full SDP+ICE exchange
    /// between two [`PeerConnection`]s, and verifies that the remote
    /// side receives the tracks through the `on_track` callback.
    ///
    /// Requires features: `video`, `audio`, `vp8`.
    /// Skipped when no camera or microphone is available.
    #[cfg(all(feature = "video", feature = "audio", feature = "vp8"))]
    #[tokio::test]
    async fn real_device_loopback() {
        use crate::media::{AudioCapture, VideoCapture};
        use crate::media::MediaManager;
        use std::sync::Arc;

        let _ = tracing_subscriber::fmt()
            .with_max_level(tracing::Level::DEBUG)
            .try_init();

        ensure_crypto_provider();
        let config = CallConfig::default();

        // ---- Open real devices ----

        let audio_cap = AudioCapture::try_new();
        let video_cap = VideoCapture::try_new();

        if audio_cap.is_err() || video_cap.is_err() {
            eprintln!(
                "Skipping real_device_loopback: audio={:?}, video={:?}",
                audio_cap.as_ref().err(),
                video_cap.as_ref().err(),
            );
            return; // Not a failure — device may not be available in CI
        }

        let audio_cap = audio_cap.unwrap();
        let video_cap = video_cap.unwrap();

        let audio_track: Arc<dyn webrtc::track::track_local::TrackLocal + Send + Sync> =
            audio_cap.track();
        let video_track: Arc<dyn webrtc::track::track_local::TrackLocal + Send + Sync> =
            video_cap.track();

        let mut alice_media = MediaManager::new();
        alice_media.set_audio_track(audio_track);
        alice_media.set_video_track(video_track);

        // ---- Alice creates PC with media tracks ----

        let alice_pc = PeerConnection::new(&config).await.unwrap();
        alice_pc.create_data_channel("real-loopback").await.unwrap();
        alice_media
            .add_tracks_to_connection(&alice_pc)
            .await
            .unwrap();

        let mut alice_rx = alice_pc.take_signaling_receiver().unwrap();
        let alice = Arc::new(alice_pc);

        // ---- Bob creates PC with on_track callback ----

        let bob_pc = PeerConnection::new(&config).await.unwrap();
        bob_pc.create_data_channel("real-loopback").await.unwrap();
        let (track_tx, mut track_rx) =
            tokio::sync::mpsc::channel::<String>(8);

        bob_pc.on_track(move |track, _receiver| {
            let tx = track_tx.clone();
            async move {
                let _ = tx
                    .send(format!(
                        "{}:{}",
                        track.kind(),
                        track.stream_id()
                    ))
                    .await;
            }
        });

        let mut bob_rx = bob_pc.take_signaling_receiver().unwrap();
        let bob = Arc::new(bob_pc);

        // ---- ICE candidate relay ----

        let alice_for_relay = alice.clone();
        let bob_for_relay = bob.clone();

        let relay = tokio::spawn(async move {
            loop {
                tokio::select! {
                    maybe_msg = alice_rx.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(c)) => {
                                let _ = bob_for_relay.add_ice_candidate(c).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                    maybe_msg = bob_rx.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(c)) => {
                                let _ = alice_for_relay.add_ice_candidate(c).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                }
            }
        });

        // ---- SDP exchange ----

        let offer = alice.create_offer().await.unwrap();
        bob.set_remote_description(offer).await.unwrap();
        let answer = bob.create_answer().await.unwrap();
        alice.set_remote_description(answer).await.unwrap();

        // ---- Wait for Connected ----

        let deadline =
            tokio::time::Instant::now() + Duration::from_secs(30);

        loop {
            let alice_state = alice.connection_state();
            let bob_state = bob.connection_state();

            if alice_state == PeerConnectionState::Connected
                && bob_state == PeerConnectionState::Connected
            {
                break;
            }

            if tokio::time::Instant::now() > deadline {
                relay.abort();
                panic!(
                    "ICE negotiation timed out after 30s: alice={alice_state:?} bob={bob_state:?}"
                );
            }

            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        relay.abort();

        // ---- Verify connection state ----

        assert_eq!(
            alice.connection_state(),
            PeerConnectionState::Connected,
            "Alice should be Connected"
        );
        assert_eq!(
            bob.connection_state(),
            PeerConnectionState::Connected,
            "Bob should be Connected"
        );

        // ---- Verify remote tracks received ----
        // Real cameras may take longer to produce the first frame,
        // so poll with a timeout instead of a single sleep+try_recv.

        let mut received = Vec::new();

        for _ in 0..150 {
            tokio::time::sleep(Duration::from_millis(200)).await;
            while let Ok(kind) = track_rx.try_recv() {
                received.push(kind);
            }
            // Once we have audio+video we're done
            let has_audio = received.iter().any(|s| s.starts_with("audio"));
            let has_video = received.iter().any(|s| s.starts_with("video"));
            if has_audio && has_video {
                break;
            }
        }

        assert!(
            !received.is_empty(),
            "Bob should have received at least one remote track, got: {:?}",
            received
        );

        let audio_count = received
            .iter()
            .filter(|s| s.starts_with("audio"))
            .count();
        let video_count = received
            .iter()
            .filter(|s| s.starts_with("video"))
            .count();

        assert!(
            audio_count >= 1,
            "Expected at least 1 audio track, got {} (received: {:?})",
            audio_count,
            received
        );
        assert!(
            video_count >= 1,
            "Expected at least 1 video track, got {} (received: {:?})",
            video_count,
            received
        );
    }

    // ---------------------------------------------------------------
    // Test: multi-party loopback (3-party star topology)
    // ---------------------------------------------------------------

    /// Creates three [`PeerConnection`]s (A, B, C) with A connected to
    /// both B and C in a star topology.  A injects external audio and
    /// video tracks.  Verifies that both B and C receive the same tracks
    /// from A with correct track counts.
    #[cfg(all(feature = "video", feature = "audio", feature = "vp8"))]
    #[tokio::test]
    async fn multi_party_loopback() {
        use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
        use webrtc::track::track_local::TrackLocal;
        use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
        use webrtc::media::Sample;
        use crate::media::MediaManager;

        ensure_crypto_provider();
        let config = CallConfig::default();

        // ---- Mock external tracks on A (no real devices) ----

        let audio_sample_track = Arc::new(
            TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: "audio/opus".to_owned(),
                    clock_rate: 48000,
                    channels: 2,
                    ..Default::default()
                },
                "audio".to_owned(),
                "test-audio".to_owned(),
            ),
        );
        let audio_track: Arc<dyn TrackLocal + Send + Sync> = audio_sample_track.clone();

        let video_sample_track = Arc::new(
            TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: "video/VP8".to_owned(),
                    clock_rate: 90000,
                    ..Default::default()
                },
                "video".to_owned(),
                "test-video".to_owned(),
            ),
        );
        let video_track: Arc<dyn TrackLocal + Send + Sync> = video_sample_track.clone();

        let mut a_media = MediaManager::new();
        a_media.set_audio_track(audio_track);
        a_media.set_video_track(video_track);

        // ---- A creates two PCs (A→B and A→C) ----

        let a_to_b_pc = PeerConnection::new(&config).await.unwrap();
        a_to_b_pc.create_data_channel("ab-data").await.unwrap();
        a_media.add_tracks_to_connection(&a_to_b_pc).await.unwrap();

        let a_to_c_pc = PeerConnection::new(&config).await.unwrap();
        a_to_c_pc.create_data_channel("ac-data").await.unwrap();
        a_media.add_tracks_to_connection(&a_to_c_pc).await.unwrap();

        let mut ab_signaling = a_to_b_pc.take_signaling_receiver().unwrap();
        let mut ac_signaling = a_to_c_pc.take_signaling_receiver().unwrap();
        let a_to_b = Arc::new(a_to_b_pc);
        let a_to_c = Arc::new(a_to_c_pc);

        // ---- B creates PC with on_track callback ----

        let b_pc = PeerConnection::new(&config).await.unwrap();
        b_pc.create_data_channel("ab-data").await.unwrap();
        let (b_track_tx, mut b_track_rx) =
            tokio::sync::mpsc::channel::<String>(8);

        b_pc.on_track({
            let tx = b_track_tx.clone();
            move |track, _receiver| {
                let tx = tx.clone();
                async move {
                    let _ = tx
                        .send(format!("{}:{}", track.kind(), track.stream_id()))
                        .await;
                }
            }
        });

        let mut b_signaling = b_pc.take_signaling_receiver().unwrap();
        let b = Arc::new(b_pc);

        // ---- C creates PC with on_track callback ----

        let c_pc = PeerConnection::new(&config).await.unwrap();
        c_pc.create_data_channel("ac-data").await.unwrap();
        let (c_track_tx, mut c_track_rx) =
            tokio::sync::mpsc::channel::<String>(8);

        c_pc.on_track({
            let tx = c_track_tx.clone();
            move |track, _receiver| {
                let tx = tx.clone();
                async move {
                    let _ = tx
                        .send(format!("{}:{}", track.kind(), track.stream_id()))
                        .await;
                }
            }
        });

        let mut c_signaling = c_pc.take_signaling_receiver().unwrap();
        let c = Arc::new(c_pc);

        // ---- ICE candidate relay (star: A↔B + A↔C) ----

        let a_to_b_relay = a_to_b.clone();
        let a_to_c_relay = a_to_c.clone();
        let b_relay = b.clone();
        let c_relay = c.clone();

        let relay = tokio::spawn(async move {
            loop {
                tokio::select! {
                    // A→B ICE
                    maybe_msg = ab_signaling.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(cand)) => {
                                let _ = b_relay.add_ice_candidate(cand).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                    // A→C ICE
                    maybe_msg = ac_signaling.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(cand)) => {
                                let _ = c_relay.add_ice_candidate(cand).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                    // B→A ICE
                    maybe_msg = b_signaling.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(cand)) => {
                                let _ = a_to_b_relay.add_ice_candidate(cand).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                    // C→A ICE
                    maybe_msg = c_signaling.recv() => {
                        match maybe_msg {
                            Some(SignalingMessage::IceCandidate(cand)) => {
                                let _ = a_to_c_relay.add_ice_candidate(cand).await;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                }
            }
        });

        // ---- SDP exchange: A→B and A→C ----

        // A→B
        let offer_ab = a_to_b.create_offer().await.unwrap();
        b.set_remote_description(offer_ab).await.unwrap();
        let answer_b = b.create_answer().await.unwrap();
        a_to_b.set_remote_description(answer_b).await.unwrap();

        // A→C
        let offer_ac = a_to_c.create_offer().await.unwrap();
        c.set_remote_description(offer_ac).await.unwrap();
        let answer_c = c.create_answer().await.unwrap();
        a_to_c.set_remote_description(answer_c).await.unwrap();

        // ---- Continuously write samples from A ----

        let writer_audio = audio_sample_track.clone();
        let writer_video = video_sample_track.clone();
        let _writer = tokio::spawn(async move {
            loop {
                let ts = std::time::SystemTime::now();
                let _ = writer_audio.write_sample(&Sample {
                    data: bytes::Bytes::from(vec![0u8; 960]),
                    duration: Duration::from_millis(20),
                    timestamp: ts,
                    ..Default::default()
                }).await;
                let _ = writer_video.write_sample(&Sample {
                    data: bytes::Bytes::from(vec![0u8; 100]),
                    duration: Duration::from_millis(33),
                    timestamp: ts,
                    ..Default::default()
                }).await;
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        });

        // ---- Wait for all connections to reach Connected ----
        // We wait for A↔B and A↔C both connected.
        {
            let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
            loop {
                let ab_state = a_to_b.connection_state();
                let b_state = b.connection_state();
                let ac_state = a_to_c.connection_state();
                let c_state = c.connection_state();

                let ab_ok = ab_state == PeerConnectionState::Connected
                    && b_state == PeerConnectionState::Connected;
                let ac_ok = ac_state == PeerConnectionState::Connected
                    && c_state == PeerConnectionState::Connected;

                if ab_ok && ac_ok {
                    break;
                }

                if tokio::time::Instant::now() > deadline {
                    relay.abort();
                    panic!(
                        "ICE negotiation timed out after 20s: \
                         A→B: a={ab_state:?} b={b_state:?}, \
                         A→C: a={ac_state:?} c={c_state:?}"
                    );
                }

                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        }

        relay.abort();

        // Give RTP packets time to flow after ICE/DTLS completes
        tokio::time::sleep(Duration::from_millis(800)).await;

        // ---- Verify connection states ----

        assert_eq!(
            a_to_b.connection_state(),
            PeerConnectionState::Connected,
            "A→B should be Connected"
        );
        assert_eq!(
            b.connection_state(),
            PeerConnectionState::Connected,
            "B should be Connected"
        );
        assert_eq!(
            a_to_c.connection_state(),
            PeerConnectionState::Connected,
            "A→C should be Connected"
        );
        assert_eq!(
            c.connection_state(),
            PeerConnectionState::Connected,
            "C should be Connected"
        );

        // ---- Verify B received tracks from A ----

        let mut b_received = Vec::new();
        while let Ok(kind) = b_track_rx.try_recv() {
            b_received.push(kind);
        }
        assert!(
            !b_received.is_empty(),
            "B should have received at least one remote track"
        );
        let b_audio = b_received.iter().filter(|s| s.starts_with("audio")).count();
        let b_video = b_received.iter().filter(|s| s.starts_with("video")).count();
        assert!(
            b_audio >= 1,
            "B expected >=1 audio track, got {} (received: {:?})",
            b_audio, b_received
        );
        assert!(
            b_video >= 1,
            "B expected >=1 video track, got {} (received: {:?})",
            b_video, b_received
        );

        // ---- Verify C received tracks from A ----

        let mut c_received = Vec::new();
        while let Ok(kind) = c_track_rx.try_recv() {
            c_received.push(kind);
        }
        assert!(
            !c_received.is_empty(),
            "C should have received at least one remote track"
        );
        let c_audio = c_received.iter().filter(|s| s.starts_with("audio")).count();
        let c_video = c_received.iter().filter(|s| s.starts_with("video")).count();
        assert!(
            c_audio >= 1,
            "C expected >=1 audio track, got {} (received: {:?})",
            c_audio, c_received
        );
        assert!(
            c_video >= 1,
            "C expected >=1 video track, got {} (received: {:?})",
            c_video, c_received
        );

        // ---- Clean hangup: close all connections ----

        let _ = a_to_b.close().await;
        let _ = a_to_c.close().await;
        let _ = b.close().await;
        let _ = c.close().await;

        // Allow close to propagate
        tokio::time::sleep(Duration::from_millis(200)).await;

        assert_eq!(
            a_to_b.connection_state(),
            PeerConnectionState::Closed,
            "A→B should be Closed"
        );
        assert_eq!(
            b.connection_state(),
            PeerConnectionState::Closed,
            "B should be Closed"
        );
        assert_eq!(
            a_to_c.connection_state(),
            PeerConnectionState::Closed,
            "A→C should be Closed"
        );
        assert_eq!(
            c.connection_state(),
            PeerConnectionState::Closed,
            "C should be Closed"
        );
    }

}
