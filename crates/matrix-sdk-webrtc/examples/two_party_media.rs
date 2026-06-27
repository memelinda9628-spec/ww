use std::sync::Arc;

use matrix_sdk::{Client, config::SyncSettings};
use matrix_sdk::ruma::OwnedRoomId;
use matrix_sdk_webrtc::{
    CallConfig, CallManager, CallType, PeerConnectionState,
    transport::{MatrixCallTransport, register_call_event_listener},
};
use tokio::sync::Mutex;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let hs = std::env::var("MATRIX_HOMESERVER")
        .unwrap_or_else(|_| "http://localhost:8008".into());
    let room_id = std::env::var("MATRIX_ROOM_ID")
        .expect("MATRIX_ROOM_ID required");
    let bob_user = std::env::var("BOB_USER")
        .unwrap_or_else(|_| "@bob7:test.local".into());
    let alice_user = std::env::var("ALICE_USER")
        .unwrap_or_else(|_| "@alice7:test.local".into());

    eprintln!("[01] build clients");
    let alice_client = Client::builder()
        .server_name_or_homeserver_url(&hs)
        .build().await?;
    let bob_client = Client::builder()
        .server_name_or_homeserver_url(&hs)
        .build().await?;

    eprintln!("[02] install crypto provider");
    matrix_sdk_webrtc::ensure_crypto_provider();

    eprintln!("[03] login alice");
    alice_client.matrix_auth()
        .login_username("alice7", "test1234")
        .initial_device_display_name("media-test")
        .send().await?;

    eprintln!("[04] login bob");
    bob_client.matrix_auth()
        .login_username("bob7", "test1234")
        .initial_device_display_name("media-test")
        .send().await?;

    eprintln!("[05] sync");
    alice_client.sync_once(SyncSettings::new().timeout(std::time::Duration::from_secs(5))).await?;
    bob_client.sync_once(SyncSettings::new().timeout(std::time::Duration::from_secs(5))).await?;
    let alice_client = &alice_client;
    let bob_client  = &bob_client;

    let room_id: OwnedRoomId = room_id.parse()?;
    eprintln!("[06] join");
    let alice_room = alice_client.join_room_by_id(&room_id).await?;
    let bob_room = bob_client.join_room_by_id(&room_id).await?;

    eprintln!("[07] CallManagers");
    let alice_cm = Arc::new(Mutex::new(CallManager::new(CallConfig::default())));
    let bob_cm = Arc::new(Mutex::new(CallManager::new(CallConfig::default())));

    alice_cm.lock().await.set_transport(Box::new(
        MatrixCallTransport::new(alice_room.clone())
    ));
    bob_cm.lock().await.set_transport(Box::new(
        MatrixCallTransport::new(bob_room.clone())
    ));

    let _alice_h = register_call_event_listener(&alice_room, alice_cm.clone());
    let _bob_h = register_call_event_listener(&bob_room, bob_cm.clone());

    // -- Act 1: Alice creates call --
    eprintln!("[08] Alice creates call ->");
    let call_id = alice_cm.lock().await
        .create_call(&bob_user, CallType::AudioVideo)
        .await?;
    eprintln!("[08] call_id = {call_id}");

    // Wait for spawned send to actually deliver the Invite
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;

    // -- Act 2: Bob syncs to receive Invite --
    eprintln!("[09] Bob syncs to receive Invite...");
    bob_client.sync_once(SyncSettings::new().timeout(std::time::Duration::from_secs(10))).await?;

    // -- Act 3: Bob polls pending invite and accepts --
    eprintln!("[10] Bob polls pending invite...");
    let (invite_call_id, offer_sdp, call_type) = bob_cm.lock().await
        .poll_pending_invite()
        .ok_or("Bob did not receive the Invite event")?;

    eprintln!("[10] invite_call_id = {invite_call_id}, call_type = {call_type:?}");

    eprintln!("[11] Bob accepts call...");
    bob_cm.lock().await
        .accept_call(invite_call_id.clone(), &alice_user, offer_sdp, call_type)
        .await?;

    eprintln!("[11] Bob state after accept: {:?}",
        bob_cm.lock().await.connection_state(&invite_call_id));

    // -- Act 4: Alice syncs to receive Answer + ICE --
    eprintln!("[12] Alice syncs to receive Answer + ICE...");
    alice_client.sync_once(SyncSettings::new().timeout(std::time::Duration::from_secs(10))).await?;

    // -- Act 5: Bob syncs again for ICE --
    eprintln!("[13] Bob syncs for ICE...");
    bob_client.sync_once(SyncSettings::new().timeout(std::time::Duration::from_secs(5))).await?;

    // -- Act 6: Alice syncs again for ICE --
    eprintln!("[14] Alice syncs again for ICE...");
    alice_client.sync_once(SyncSettings::new().timeout(std::time::Duration::from_secs(5))).await?;

    // -- Act 7: Wait for ICE -> Connected --
    eprintln!("[15] Waiting for ICE connected...");
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(20);
    loop {
        let alice_state = alice_cm.lock().await.connection_state(&call_id);
        let bob_state = bob_cm.lock().await.connection_state(&invite_call_id);
        eprintln!("[15] alice={alice_state:?}, bob={bob_state:?}");

        if alice_state == Some(PeerConnectionState::Connected)
           && bob_state == Some(PeerConnectionState::Connected)
        {
            eprintln!("[15]  OK BOTH CONNECTED");
            break;
        }
        if tokio::time::Instant::now() > deadline {
            eprintln!("[15]  XX timeout - alice={alice_state:?}, bob={bob_state:?}");
            break;
        }
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }

    eprintln!("[done]");
    Ok(())
}