//! Matrix `m.call.*` transport bridge.
//!
//! Implements [`SignalingTransport`] by converting [`CallEvent`] to ruma
//! `m.call.*` event content types and dispatching via `Room::send()`.
//!
//! Also provides inbound conversion ([`call_event_from_ruma`]) and room-level
//! event listener registration ([`register_call_event_listener`]).

#[cfg(feature = "webrtc")]
use std::sync::Arc;

use ruma::{
    OwnedVoipId, UInt, VoipVersionId,
    events::{
        AnySyncTimelineEvent,
        call::{
            SessionDescription as RumaSdp,
            answer::CallAnswerEventContent,
            candidates::{CallCandidatesEventContent, Candidate as RumaCandidate},
            hangup::CallHangupEventContent,
            invite::CallInviteEventContent,
        },
    },
};
#[cfg(feature = "webrtc")]
use tokio::sync::Mutex;
use tracing::{debug, warn};

use crate::signaling::{CallEvent, SignalingTransport};
/// A [`SignalingTransport`] that sends `m.call.*` events through a Matrix room.
///
/// Sending is fire-and-forget via `tokio::spawn` because
/// [`SignalingTransport::send`] is synchronous while `Room::send()` is async.
#[derive(Clone)]
pub struct MatrixCallTransport {
    room: matrix_sdk::Room,
}

impl MatrixCallTransport {
    /// Create a transport bound to `room`.
    pub fn new(room: matrix_sdk::Room) -> Self {
        Self { room }
    }
}

impl SignalingTransport for MatrixCallTransport {
    fn send(&self, event: CallEvent) {
        let room = self.room.clone();
        tokio::spawn(async move {
            if let Err(e) = send_one(&room, event).await {
                warn!("Failed to send call signaling event: {e}");
            }
        });
    }
}

// ---- per-event conversion ------------------------------------------------

async fn send_one(
    room: &matrix_sdk::Room,
    event: CallEvent,
) -> Result<(), matrix_sdk::Error> {
    match event {
        CallEvent::Invite { call_id, sdp, call_type } => {
            let content = CallInviteEventContent::new(
                OwnedVoipId::from(call_id.as_str()),
                UInt::new(60_000).unwrap(),
                RumaSdp::new("offer".into(), sdp),
                VoipVersionId::V0,
            );
            debug!(%call_id, ?call_type, "Sending m.call.invite");
            room.send(content).await?;
        }
        CallEvent::Answer { call_id, sdp } => {
            let content = CallAnswerEventContent::new(
                RumaSdp::new("answer".into(), sdp),
                OwnedVoipId::from(call_id.as_str()),
                VoipVersionId::V0,
            );
            debug!(%call_id, "Sending m.call.answer");
            room.send(content).await?;
        }
        CallEvent::IceCandidates { call_id, candidates } => {
            let cs: Vec<RumaCandidate> =
                candidates.iter().map(|c| RumaCandidate::new(c.clone())).collect();
            let content = CallCandidatesEventContent::new(
                OwnedVoipId::from(call_id.as_str()),
                cs,
                VoipVersionId::V0,
            );
            debug!(%call_id, n = candidates.len(), "Sending m.call.candidates");
            room.send(content).await?;
        }
        CallEvent::Hangup { call_id, reason: _ } => {
            let content = CallHangupEventContent::new(
                OwnedVoipId::from(call_id.as_str()),
                VoipVersionId::V0,
            );
            debug!(%call_id, "Sending m.call.hangup");
            room.send(content).await?;
        }
    }
    Ok(())
}

// ---- inbound conversion --------------------------------------------------

/// Convert an incoming `m.call.*` sync timeline event to a [`CallEvent`].
///
/// Returns `None` for unsupported event types.
pub fn call_event_from_ruma(
    event: &AnySyncTimelineEvent,
) -> Option<CallEvent> {
    use ruma::events::AnySyncMessageLikeEvent;

    let AnySyncTimelineEvent::MessageLike(msg) = event else {
        return None;
    };

    match msg {
        AnySyncMessageLikeEvent::CallInvite(ev) => {
            let original = ev.as_original()?;
            Some(CallEvent::Invite {
                call_id: original.content.call_id.to_string(),
                sdp: original.content.offer.sdp.clone(),
                call_type: crate::CallType::AudioVideo,
            })
        }
        AnySyncMessageLikeEvent::CallAnswer(ev) => {
            let original = ev.as_original()?;
            Some(CallEvent::Answer {
                call_id: original.content.call_id.to_string(),
                sdp: original.content.answer.sdp.clone(),
            })
        }
        AnySyncMessageLikeEvent::CallCandidates(ev) => {
            let original = ev.as_original()?;
            let candidates = original
                .content
                .candidates
                .iter()
                .map(|c| c.candidate.clone())
                .collect();
            Some(CallEvent::IceCandidates {
                call_id: original.content.call_id.to_string(),
                candidates,
            })
        }
        AnySyncMessageLikeEvent::CallHangup(ev) => {
            let original = ev.as_original()?;
            Some(CallEvent::Hangup {
                call_id: original.content.call_id.to_string(),
                reason: Some(format!("{:?}", original.content.reason)),
            })
        }
        _ => None,
    }
}

// ---- room event listener -------------------------------------------------

/// Register event handlers on `room` that convert incoming `m.call.*`
/// events to [`CallEvent`] and forward them to `call_manager`.
///
/// Returns an [`EventHandlerHandle`]; drop it to unregister all handlers.
#[cfg(feature = "webrtc")]
pub fn register_call_event_listener(
    room: &matrix_sdk::Room,
    call_manager: Arc<Mutex<crate::CallManager>>,
) -> matrix_sdk::event_handler::EventHandlerHandle {
    use ruma::events::{
        AnySyncMessageLikeEvent,
        call::{
            answer::SyncCallAnswerEvent,
            candidates::SyncCallCandidatesEvent,
            hangup::SyncCallHangupEvent,
            invite::SyncCallInviteEvent,
        },
        AnySyncTimelineEvent,
    };

    let cm_invite = call_manager.clone();
    let h1 = room.add_event_handler(
        move |event: SyncCallInviteEvent| {
            let cm = cm_invite.clone();
            async move {
                let any_msg: AnySyncMessageLikeEvent = event.into();
                let any: AnySyncTimelineEvent = any_msg.into();
                let Some(ce) = call_event_from_ruma(&any) else { return };
                debug!("m.call.invite → {:?}", ce);
                let mut guard = cm.lock().await;
                let _ = guard.on_signaling_event(&ce).await;
            }
        },
    );

    let cm_answer = call_manager.clone();
    let _h2 = room.add_event_handler(
        move |event: SyncCallAnswerEvent| {
            let cm = cm_answer.clone();
            async move {
                let any_msg: AnySyncMessageLikeEvent = event.into();
                let any: AnySyncTimelineEvent = any_msg.into();
                let Some(ce) = call_event_from_ruma(&any) else { return };
                debug!("m.call.answer → {:?}", ce);
                let mut guard = cm.lock().await;
                let _ = guard.on_signaling_event(&ce).await;
            }
        },
    );

    let cm_cand = call_manager.clone();
    let _h3 = room.add_event_handler(
        move |event: SyncCallCandidatesEvent| {
            let cm = cm_cand.clone();
            async move {
                let any_msg: AnySyncMessageLikeEvent = event.into();
                let any: AnySyncTimelineEvent = any_msg.into();
                let Some(ce) = call_event_from_ruma(&any) else { return };
                debug!("m.call.candidates ({} items)", count_candidates(&ce));
                let mut guard = cm.lock().await;
                let _ = guard.on_signaling_event(&ce).await;
            }
        },
    );

    let cm_hup = call_manager.clone();
    let _h4 = room.add_event_handler(
        move |event: SyncCallHangupEvent| {
            let cm = cm_hup.clone();
            async move {
                let any_msg: AnySyncMessageLikeEvent = event.into();
                let any: AnySyncTimelineEvent = any_msg.into();
                let Some(ce) = call_event_from_ruma(&any) else { return };
                debug!("m.call.hangup → {:?}", ce);
                let mut guard = cm.lock().await;
                let _ = guard.on_signaling_event(&ce).await;
            }
        },
    );

    // Return the first handle as representative; all four handlers live
    // as long as the caller holds at least one handle.
    h1
}

#[cfg(feature = "webrtc")]
fn count_candidates(ce: &CallEvent) -> usize {
    match ce {
        CallEvent::IceCandidates { candidates, .. } => candidates.len(),
        _ => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::CallType;

    fn make_invite_json() -> serde_json::Value {
        serde_json::json!({
            "type": "m.call.invite",
            "event_id": "$ev1:matrix.org",
            "sender": "@alice:matrix.org",
            "origin_server_ts": 1000,
            "content": {
                "call_id": "!call123:matrix.org",
                "offer": { "type": "offer", "sdp": "v=0\no=SDP" },
                "lifetime": 60000,
                "version": "0"
            }
        })
    }

    #[test]
    fn convert_invite() {
        let raw: serde_json::Value = make_invite_json();
        let event: AnySyncTimelineEvent =
            serde_json::from_value(raw).expect("parse invite");
        let ce = call_event_from_ruma(&event).expect("should convert invite");
        match ce {
            CallEvent::Invite { call_id, sdp, call_type } => {
                assert_eq!(call_id, "!call123:matrix.org");
                assert_eq!(sdp, "v=0\no=SDP");
                assert_eq!(call_type, CallType::AudioVideo);
            }
            _ => panic!("expected Invite, got {:?}", ce),
        }
    }

    #[test]
    fn convert_non_call_event_returns_none() {
        let raw = serde_json::json!({
            "type": "m.room.message",
            "event_id": "$ev2:matrix.org",
            "sender": "@alice:matrix.org",
            "origin_server_ts": 1000,
            "content": {
                "body": "hello",
                "msgtype": "m.text"
            }
        });
        let event: AnySyncTimelineEvent =
            serde_json::from_value(raw).expect("parse message");
        assert!(call_event_from_ruma(&event).is_none());
    }
}
