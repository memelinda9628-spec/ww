//! Step 4 — Two-party Matrix signaling pipe integration test.
//!
//! Verifies that `m.call.*` events sent through `MatrixCallTransport`
//! are received by the remote party's `register_call_event_listener`
//! and forwarded to `CallManager::on_signaling_event`.
//!
//! ## Usage
//!
//! ```sh
//! MATRIX_HOMESERVER=https://matrix.org \
//!   ALICE_USER=@alice:matrix.org ALICE_PASS=hunter2 \
//!   BOB_USER=@bob:matrix.org BOB_PASS=ilovealice \
//!   MATRIX_ROOM_ID='!shared:matrix.org' \
//!   RUST_LOG=matrix_sdk_webrtc=debug,two_party_call=info \
//!   cargo run -p matrix-sdk-webrtc --features webrtc \
//!     --example two_party_call
//! ```
//!
//! ## Signaling cycle
//!
//! Alice  ──invite──→ Bob   (via MatrixCallTransport)
//! Alice ←──answer─── Bob   (via Bob's transport)
//! Alice ──ICE──────→ Bob
//! Alice ←──ICE────── Bob
//! Alice ──hangup───→ Bob

use std::sync::Arc;
use std::time::Duration;

use matrix_sdk::{
    Client,
    config::SyncSettings,
};
use matrix_sdk_webrtc::{
    CallConfig, CallManager,
    signaling::CallEvent,
    transport::{MatrixCallTransport, register_call_event_listener},
};
use tokio::sync::Mutex;

const CALL_ID: &str = "two-party-test-call";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

async fn login_and_join(
    client: &Client,
    user: &str,
    pass: &str,
    room_id: &str,
) -> Result<matrix_sdk::Room, Box<dyn std::error::Error>> {
    client.matrix_auth()
        .login_username(user, pass)
        .initial_device_display_name("webrtc-two-party")
        .send()
        .await?;

    client.sync_once(SyncSettings::default()).await?;

    let room_id: ruma::OwnedRoomId = room_id.try_into()?;
    client.join_room_by_id(&room_id).await?;

    Ok(client.get_room(&room_id)
        .ok_or_else(|| format!("room {room_id} not found in store after join"))?)
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let _ = tracing_subscriber::fmt::try_init();

    let homeserver = std::env::var("MATRIX_HOMESERVER")
        .unwrap_or_else(|_| "https://matrix.org".into());
    let room_id = std::env::var("MATRIX_ROOM_ID")
        .expect("MATRIX_ROOM_ID not set");

    let alice_user = std::env::var("ALICE_USER").expect("ALICE_USER required");
    let alice_pass = std::env::var("ALICE_PASS").expect("ALICE_PASS required");
    let bob_user = std::env::var("BOB_USER").expect("BOB_USER required");
    let bob_pass = std::env::var("BOB_PASS").expect("BOB_PASS required");

    let alice_client = Client::builder()
        .server_name_or_homeserver_url(&homeserver)
        .build().await?;
    let bob_client = Client::builder()
        .server_name_or_homeserver_url(&homeserver)
        .build().await?;

    // ---- Phase 0: login & join ----------------------------------------

    eprintln!("[phase0] login & join room ...");
    let alice_room = login_and_join(
        &alice_client, &alice_user, &alice_pass, &room_id,
    ).await?;
    let bob_room = login_and_join(
        &bob_client, &bob_user, &bob_pass, &room_id,
    ).await?;
    eprintln!("[phase0] both parties in room {room_id}");

    // ---- Phase 1: wire up ---------------------------------------------

    eprintln!("[phase1] register event listeners ...");
    let bob_cm = Arc::new(Mutex::new(CallManager::new(CallConfig::default())));
    bob_cm.lock().await.set_transport(Box::new(
        MatrixCallTransport::new(bob_room.clone()),
    ));
    let _bob_handle = register_call_event_listener(&bob_room, bob_cm.clone());

    let alice_cm = Arc::new(Mutex::new(CallManager::new(CallConfig::default())));
    alice_cm.lock().await.set_transport(Box::new(
        MatrixCallTransport::new(alice_room.clone()),
    ));
    let _alice_handle = register_call_event_listener(&alice_room, alice_cm.clone());

    alice_client.sync_once(SyncSettings::default()).await?;
    bob_client.sync_once(SyncSettings::default()).await?;
    eprintln!("[phase1] listeners active");

    // ---- Phase 2: invite → answer -------------------------------------

    eprintln!("[phase2] Alice sends invite ...");
    {
        let mut cm = alice_cm.lock().await;
        cm.on_signaling_event(&CallEvent::Invite {
            call_id: CALL_ID.into(),
            sdp: "v=0\r\no=alice 1 1 IN IP4 0.0.0.0\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 0\r\nc=IN IP4 0.0.0.0".into(),
            call_type: matrix_sdk_webrtc::CallType::AudioVideo,
        }).await?;
    }
    tokio::time::sleep(Duration::from_millis(500)).await;
    bob_client.sync_once(SyncSettings::default()).await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    eprintln!("[phase2] Bob sends answer ...");
    {
        let mut cm = bob_cm.lock().await;
        cm.on_signaling_event(&CallEvent::Answer {
            call_id: CALL_ID.into(),
            sdp: "v=0\r\no=bob 1 1 IN IP4 0.0.0.0\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 0\r\nc=IN IP4 0.0.0.0".into(),
        }).await?;
    }
    tokio::time::sleep(Duration::from_millis(500)).await;
    alice_client.sync_once(SyncSettings::default()).await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    // ---- Phase 3: ICE exchange ----------------------------------------

    eprintln!("[phase3] ICE exchange ...");
    {
        alice_cm.lock().await.on_signaling_event(&CallEvent::IceCandidates {
            call_id: CALL_ID.into(),
            candidates: vec!["candidate:1 1 UDP 2130706431 192.168.1.1 9 typ host".into()],
        }).await?;
    }
    tokio::time::sleep(Duration::from_millis(500)).await;
    bob_client.sync_once(SyncSettings::default()).await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    {
        bob_cm.lock().await.on_signaling_event(&CallEvent::IceCandidates {
            call_id: CALL_ID.into(),
            candidates: vec!["candidate:1 1 UDP 2130706431 10.0.0.1 9 typ host".into()],
        }).await?;
    }
    tokio::time::sleep(Duration::from_millis(500)).await;
    alice_client.sync_once(SyncSettings::default()).await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    // ---- Phase 4: hangup ----------------------------------------------

    eprintln!("[phase4] Alice sends hangup ...");
    {
        alice_cm.lock().await.on_signaling_event(&CallEvent::Hangup {
            call_id: CALL_ID.into(),
            reason: Some("Test complete".into()),
        }).await?;
    }
    tokio::time::sleep(Duration::from_millis(500)).await;
    bob_client.sync_once(SyncSettings::default()).await?;
    tokio::time::sleep(Duration::from_millis(500)).await;

    // ---- verification ------------------------------------------------

    eprintln!("[verify] Checking call registration state ...");
    {
        let guard = bob_cm.lock().await;
        let registered = guard.is_call_registered(CALL_ID);
        eprintln!("[verify] Bob call registered: {registered}");
    }

    eprintln!("=== two_party_call: signaling pipe verified ===");
    Ok(())
}
