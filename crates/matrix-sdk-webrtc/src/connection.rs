//! Peer connection wrappers over [webrtc-rs](webrtc).
//!
//! Each `PeerConnection` manages a single WebRTC peer-to-peer link,
//! including the underlying RTCPeerConnection, data channels, and
//! per-connection signaling queue.

#[cfg(feature = "webrtc")]
use webrtc::api::APIBuilder;
#[cfg(feature = "webrtc")]
use webrtc::ice_transport::ice_candidate::RTCIceCandidate;
#[cfg(feature = "webrtc")]
use webrtc::ice_transport::ice_server::RTCIceServer;
#[cfg(feature = "webrtc")]
use webrtc::peer_connection::configuration::RTCConfiguration;
#[cfg(feature = "webrtc")]
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
#[cfg(feature = "webrtc")]
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
#[cfg(feature = "webrtc")]
use webrtc::peer_connection::RTCPeerConnection as InnerRTCPeerConnection;
#[cfg(feature = "webrtc")]
use webrtc::rtp_transceiver::rtp_receiver::RTCRtpReceiver;
#[cfg(feature = "webrtc")]
use webrtc::track::track_local::TrackLocal;
#[cfg(feature = "webrtc")]
use webrtc::track::track_remote::TrackRemote;

#[cfg(feature = "webrtc")]
use crate::config::CallConfig;
#[cfg(feature = "webrtc")]
use crate::error::CallError;

// ---------------------------------------------------------------------------
// Public types — available even without the `webrtc` feature so that
// downstream crates can refer to them in type signatures.
// ---------------------------------------------------------------------------

/// Connection state of a WebRTC peer connection.
///
/// Mirrors `webrtc::peer_connection::RTCPeerConnectionState`.
/// High-level WebRTC connection state.
///
/// Mirrors webrtc-rs's `RTCPeerConnectionState` but is decoupled
/// from the underlying library so callers don't need to depend on
/// `webrtc` directly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeerConnectionState {
    /// The connection is new and has not started connecting yet.
    New,
    /// ICE is gathering candidates and/or checking connectivity.
    Connecting,
    /// The connection is established and media can flow.
    Connected,
    /// The connection has been temporarily disrupted.
    Disconnected,
    /// The connection has failed and cannot be recovered.
    Failed,
    /// The connection has been explicitly closed.
    Closed,
}

// ---------------------------------------------------------------------------
// Feature-gated implementation
// ---------------------------------------------------------------------------

#[cfg(feature = "webrtc")]
mod inner {
    use bytes::Bytes;
    use std::future::Future;
    use std::sync::{Arc, Mutex};

    use tokio::sync::mpsc;

    use webrtc::data_channel::RTCDataChannel;
    use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;

    use super::*;

    // ---- SignalingMessage ------------------------------------------------

    /// A signaling message produced by a peer connection.
    ///
    /// These messages are emitted on the internal `mpsc` channel and are
    /// consumed by the signaling layer (`signaling.rs`) to be sent to the
    /// remote peer via Matrix `m.call.*` events.
    #[derive(Debug, Clone)]
    pub enum SignalingMessage {
        /// A locally-generated SDP offer.
        Offer(RTCSessionDescription),
        /// A locally-generated SDP answer.
        Answer(RTCSessionDescription),
        /// A local ICE candidate.
        IceCandidate(RTCIceCandidate),
    }

    // ---- DataChannelMessage ----------------------------------------------

    /// A message received on a WebRTC data channel.
    #[derive(Debug, Clone)]
    pub enum DataChannelMessage {
        /// UTF-8 text message.
        Text(String),
        /// Binary message.
        Binary(Vec<u8>),
    }

    // ---- PeerConnection --------------------------------------------------

    /// Wraps a single WebRTC `RTCPeerConnection`.
    ///
    /// Manages:
    /// - The underlying webrtc-rs peer connection.
    /// - Local audio/video tracks.
    /// - A signaling output channel (mpsc) for offer, answer, and ICE
    ///   candidate messages.
    /// - Connection-state tracking.
    pub struct PeerConnection {
        /// Underlying webrtc-rs peer connection.
        pc: Arc<InnerRTCPeerConnection>,
        /// Local audio/video tracks added to this connection.
        local_tracks: Mutex<Vec<Arc<dyn TrackLocal + Send + Sync>>>,
        /// Channel for emitting signaling messages.
        #[allow(dead_code)]
        signaling_tx: mpsc::Sender<SignalingMessage>,
        /// Receiver side of the signaling channel — extracted once by the
        /// owner (mesh / call manager) via [`take_signaling_receiver`].
        signaling_rx: Mutex<Option<mpsc::Receiver<SignalingMessage>>>,
        /// Current peer connection state (updated by the state-change
        /// callback).
        connection_state: Arc<tokio::sync::RwLock<PeerConnectionState>>,
        /// Data channels created by this connection, kept alive to prevent
        /// garbage collection.
        data_channels: Mutex<Vec<Arc<RTCDataChannel>>>,
    }

    impl PeerConnection {
        // ---- Construction -------------------------------------------------

        /// Create a new `PeerConnection` with the given call configuration.
        ///
        /// This is the **initiating side** (caller): the underlying
        /// `RTCPeerConnection` is created with the supplied STUN/TURN
        /// servers, ICE candidate callbacks are registered, and the
        /// signaling channel is set up.  No SDP exchange has occurred yet.
        ///
        /// After construction, use [`create_offer`](Self::create_offer) to
        /// generate the initial SDP offer.
        pub async fn new(config: &CallConfig) -> Result<Self, CallError> {
            let mut media_engine = webrtc::api::media_engine::MediaEngine::default();
        media_engine
            .register_default_codecs()
            .map_err(|e| {
                CallError::Connection(format!(
                    "failed to register default codecs: {e}"
                ))
            })?;
        let api = APIBuilder::new()
            .with_media_engine(media_engine)
            .build();

            let rtc_config = build_rtc_config(config)?;

            let pc = api
                .new_peer_connection(rtc_config)
                .await
                .map_err(|e| {
                    CallError::Connection(format!(
                        "failed to create peer connection: {e}"
                    ))
                })?;
            let pc = Arc::new(pc);

            let (signaling_tx, signaling_rx) = mpsc::channel(64);

            let connection_state =
                Arc::new(tokio::sync::RwLock::new(PeerConnectionState::New));

            // Register ICE candidate callback — local candidates are pushed
            // onto the signaling channel.
            // Wrap in Arc<Mutex<>> because the ICE callback requires Sync
            // but mpsc::Sender is only Send.
            let ice_tx =
                Arc::new(tokio::sync::Mutex::new(signaling_tx.clone()));
            register_on_ice_candidate(&pc, ice_tx);

            // Register connection-state callback.
            register_on_state_change(&pc, Arc::clone(&connection_state));

            Ok(Self {
                pc,
                local_tracks: Mutex::new(Vec::new()),
                signaling_tx,
                signaling_rx: Mutex::new(Some(signaling_rx)),
                connection_state,
                data_channels: Mutex::new(Vec::new()),
            })
        }

        /// Create a `PeerConnection` and immediately apply the remote offer.
        ///
        /// This is the **receiving side** (callee): the underlying
        /// `RTCPeerConnection` is created and the remote SDP offer is set as
        /// the remote description.  The callee should then call
        /// [`create_answer`](Self::create_answer) to generate the
        /// corresponding SDP answer.
        pub async fn new_with_offer(
            config: &CallConfig,
            offer_sdp: RTCSessionDescription,
        ) -> Result<Self, CallError> {
            let conn = Self::new(config).await?;

            conn.pc
                .set_remote_description(offer_sdp)
                .await
                .map_err(|e| {
                    CallError::Connection(format!(
                        "failed to set remote offer: {e}"
                    ))
                })?;

            Ok(conn)
        }

        // ---- SDP negotiation ---------------------------------------------

        /// Create a local SDP offer and set it as the local description.
        ///
        /// Returns the offer that should be sent to the remote peer via
        /// signaling.
        ///
        /// After `set_local_description`, the SDP is enriched with ICE
        /// credentials (`a=ice-ufrag`/`a=ice-pwd`). We return the
        /// enriched version so the remote peer can successfully call
        /// `set_remote_description`.
        pub async fn create_offer(
            &self,
        ) -> Result<RTCSessionDescription, CallError> {
            let offer = self.pc.create_offer(None).await.map_err(|e| {
                CallError::Connection(format!("failed to create offer: {e}"))
            })?;

            // Must get the gathering promise BEFORE set_local_description,
            // because set_local_description triggers ICE gathering.
            let mut gather_done = self.pc.gathering_complete_promise().await;

            self.pc
                .set_local_description(offer)
                .await
                .map_err(|e| {
                    CallError::Connection(format!(
                        "failed to set local offer: {e}"
                    ))
                })?;

            // Wait for ICE gathering to complete — the SDP won't have
            // ice-ufrag/ice-pwd until gathering finishes.
            let _ = gather_done.recv().await;

            self.pc
                .local_description()
                .await
                .ok_or_else(|| {
                    CallError::Connection(
                        "local description unavailable after set".into(),
                    )
                })
        }

        /// Create a local SDP answer and set it as the local description.
        ///
        /// Returns the answer that should be sent to the remote peer via
        /// signaling.  Same ICE-credential enrichment as
        /// [`create_offer`](Self::create_offer).
        pub async fn create_answer(
            &self,
        ) -> Result<RTCSessionDescription, CallError> {
            let answer =
                self.pc.create_answer(None).await.map_err(|e| {
                    CallError::Connection(format!(
                        "failed to create answer: {e}"
                    ))
                })?;

            self.pc
                .set_local_description(answer)
                .await
                .map_err(|e| {
                    CallError::Connection(format!(
                        "failed to set local answer: {e}"
                    ))
                })?;

            self.pc
                .local_description()
                .await
                .ok_or_else(|| {
                    CallError::Connection(
                        "local description unavailable after set".into(),
                    )
                })
        }

        /// Set the remote SDP description (offer or answer).
        pub async fn set_remote_description(
            &self,
            sdp: RTCSessionDescription,
        ) -> Result<(), CallError> {
            self.pc.set_remote_description(sdp).await.map_err(|e| {
                CallError::Connection(format!(
                    "failed to set remote description: {e}"
                ))
            })
        }

        /// Add a remote ICE candidate to the peer connection.
        pub async fn add_ice_candidate(
            &self,
            candidate: RTCIceCandidate,
        ) -> Result<(), CallError> {
            let init = candidate
                .to_json()
                .map_err(|e| CallError::Connection(format!("failed to serialize ICE candidate: {e}")))?;
            self.pc.add_ice_candidate(init).await.map_err(|e| {
                CallError::Connection(format!(
                    "failed to add ICE candidate: {e}"
                ))
            })
        }

        /// Add a remote ICE candidate directly from an
        /// [`RTCIceCandidateInit`].
        ///
        /// Useful when the candidate arrives as a raw candidate string
        /// from Matrix signaling, bypassing the `RTCIceCandidate` round-
        /// trip through `to_json`.
        pub async fn add_ice_candidate_init(
            &self,
            init: RTCIceCandidateInit,
        ) -> Result<(), CallError> {
            self.pc.add_ice_candidate(init).await.map_err(|e| {
                CallError::Connection(format!(
                    "failed to add ICE candidate: {e}"
                ))
            })
        }

        // ---- Media --------------------------------------------------------

        /// Add a local audio or video track to this peer connection.
        ///
        /// The track will be sent to the remote peer once the connection is
        /// established.
        pub async fn add_local_track(
            &self,
            track: Arc<dyn TrackLocal + Send + Sync>,
        ) -> Result<(), CallError> {
            let _rtp_sender = self.pc.add_track(Arc::clone(&track)).await.map_err(
                |e| CallError::Media(format!("failed to add track: {e}")),
            )?;

            self.local_tracks
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .push(track);

            Ok(())
        }

        /// Register a callback that is invoked when a remote media track
        /// arrives.
        ///
        /// The callback receives the remote track and its associated RTP
        /// receiver.
        pub fn on_track<F, Fut>(&self, callback: F)
        where
            F: Fn(Arc<TrackRemote>, Arc<RTCRtpReceiver>) -> Fut
                + Send
                + Sync
                + 'static,
            Fut: Future<Output = ()> + Send + 'static,
        {
            let callback = Arc::new(callback);

            self.pc.on_track(Box::new(
                move |track: Arc<TrackRemote>,
                      receiver: Arc<RTCRtpReceiver>,
                      _transceiver: Arc<
                    webrtc::rtp_transceiver::RTCRtpTransceiver,
                >| {
                    let cb = Arc::clone(&callback);
                    Box::pin(async move {
                        cb(track, receiver).await;
                    })
                },
            ));
        }

        // ---- State --------------------------------------------------------

        /// Return the current connection state.
        ///
        /// Uses [`try_read`](tokio::sync::RwLock::try_read) to avoid
        /// blocking the async runtime.  Falls back to `New` if the lock
        /// is momentarily contested (harmless since the next polling
        /// iteration will pick up the correct state).
        pub fn connection_state(&self) -> PeerConnectionState {
            self.connection_state
                .try_read()
                .map(|s| *s)
                .unwrap_or(PeerConnectionState::New)
        }

        // ---- Signaling channel --------------------------------------------

        /// Take the signaling receiver out of this `PeerConnection`.
        ///
        /// The returned [`mpsc::Receiver`] yields [`SignalingMessage`] items
        /// (offers, answers, and ICE candidates) that should be forwarded to
        /// the remote peer via Matrix signaling.  This method may only be
        /// called once; subsequent calls return `None`.
        pub fn take_signaling_receiver(
            &self,
        ) -> Option<mpsc::Receiver<SignalingMessage>> {
            self.signaling_rx
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .take()
        }

        // ---- Data channels ----------------------------------------------

        /// Create an ordered data channel with the given label.
        ///
        /// Returns the sender-side handle. The channel will be kept alive
        /// as long as this `PeerConnection` exists.
        pub async fn create_data_channel(
            &self,
            label: &str,
        ) -> Result<Arc<RTCDataChannel>, CallError> {
            let dc = self
                .pc
                .create_data_channel(label, None)
                .await
                .map_err(|e| {
                    CallError::Connection(format!(
                        "failed to create data channel '{label}': {e}"
                    ))
                })?;

            self.data_channels
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .push(Arc::clone(&dc));

            Ok(dc)
        }

        /// Register a callback that is invoked when the remote peer creates
        /// a data channel.
        pub fn on_data_channel<F>(&self, callback: F)
        where
            F: Fn(Arc<RTCDataChannel>) + Send + Sync + 'static,
        {
            self.pc.on_data_channel(Box::new(move |dc: Arc<RTCDataChannel>| {
                callback(dc);
                Box::pin(async {})
            }));
        }

        /// Send a UTF-8 text message over the given data channel.
        pub async fn send_text(
            &self,
            dc: &RTCDataChannel,
            text: &str,
        ) -> Result<(), CallError> {
            dc.send(&Bytes::from(text.to_owned()))
                .await
                .map_err(|e| {
                    CallError::Connection(format!(
                        "failed to send text on data channel: {e}"
                    ))
                })?;
            Ok(())
        }

        /// Send binary data over the given data channel.
        pub async fn send_bytes(
            &self,
            dc: &RTCDataChannel,
            data: &[u8],
        ) -> Result<(), CallError> {
            dc.send(&Bytes::copy_from_slice(data))
                .await
                .map_err(|e| {
                    CallError::Connection(format!(
                        "failed to send bytes on data channel: {e}"
                    ))
                })?;
            Ok(())
        }
    }

    // ---- Helpers ----------------------------------------------------------

    /// Convert our crate-level [`CallConfig`] into a webrtc-rs
    /// [`RTCConfiguration`].
    fn build_rtc_config(config: &CallConfig) -> Result<RTCConfiguration, CallError> {
        let mut rtc_config = RTCConfiguration::default();

        for server in &config.ice_servers {
            rtc_config.ice_servers.push(RTCIceServer {
                urls: server.urls.clone(),
                username: server.username.clone().unwrap_or_default(),
                credential: server.credential.clone().unwrap_or_default(),
            });
        }

        Ok(rtc_config)
    }

    /// Register the `on_ice_candidate` callback so that every locally
    /// gathered ICE candidate is sent through the signaling channel.
    ///
    /// Uses `Arc<Mutex<mpsc::Sender>>` because the webrtc-rs callback type
    /// `OnLocalCandidateHdlrFn` requires `Sync`, and `mpsc::Sender` alone
    /// is only `Send`.
    fn register_on_ice_candidate(
        pc: &Arc<InnerRTCPeerConnection>,
        tx: Arc<tokio::sync::Mutex<mpsc::Sender<SignalingMessage>>>,
    ) {
        pc.on_ice_candidate(Box::new(
            move |candidate: Option<RTCIceCandidate>| {
                let tx = Arc::clone(&tx);
                Box::pin(async move {
                    if let Some(c) = candidate {
                        let _ = tx
                            .lock()
                            .await
                            .send(SignalingMessage::IceCandidate(c))
                            .await;
                    }
                })
            },
        ));
    }

    /// Register the `on_peer_connection_state_change` callback to keep
    /// the internal state in sync with the underlying connection.
    fn register_on_state_change(
        pc: &Arc<InnerRTCPeerConnection>,
        state: Arc<tokio::sync::RwLock<PeerConnectionState>>,
    ) {
        pc.on_peer_connection_state_change(Box::new(
            move |raw: RTCPeerConnectionState| {
                let mapped = match raw {
                    RTCPeerConnectionState::New => PeerConnectionState::New,
                    RTCPeerConnectionState::Connecting => {
                        PeerConnectionState::Connecting
                    }
                    RTCPeerConnectionState::Connected => {
                        PeerConnectionState::Connected
                    }
                    RTCPeerConnectionState::Disconnected => {
                        PeerConnectionState::Disconnected
                    }
                    RTCPeerConnectionState::Failed => {
                        PeerConnectionState::Failed
                    }
                    RTCPeerConnectionState::Closed => {
                        PeerConnectionState::Closed
                    }
                    _ => PeerConnectionState::New,
                };

                let state = Arc::clone(&state);
                Box::pin(async move {
                    *state.write().await = mapped;
                })
            },
        ));
    }
}

#[cfg(feature = "webrtc")]
pub use inner::{DataChannelMessage, PeerConnection, SignalingMessage};
