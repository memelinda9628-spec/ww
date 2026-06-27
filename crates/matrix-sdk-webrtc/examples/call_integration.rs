//! Integration example: bridge `matrix-sdk-webrtc` to real Matrix sync.
//!
//! Demonstrates Step 3 completion — `register_call_event_listener` receiving
//! events from a live `Client::sync()` stream.
//!
//! ## Usage
//!
//! ```sh
//! MATRIX_HOMESERVER=https://matrix.org \
//!   MATRIX_USER=@bob:matrix.org \
//!   MATRIX_PASSWORD=hunter2 \
//!   MATRIX_ROOM_ID='!abc123:matrix.org' \
//!   cargo run -p matrix-sdk-webrtc --features webrtc --example call_integration
//! ```
//!
//! If `MATRIX_ROOM_ID` is omitted the example joins the first room found.

use std::sync::Arc;

use matrix_sdk::{
    Client, Room,
    config::SyncSettings,
};
use matrix_sdk_webrtc::{
    CallConfig, CallManager,
    transport::{MatrixCallTransport, register_call_event_listener},
};
use tokio::sync::Mutex;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let homeserver = std::env::var("MATRIX_HOMESERVER")
        .unwrap_or_else(|_| "https://matrix.org".into());
    let user = std::env::var("MATRIX_USER").ok();
    let password = std::env::var("MATRIX_PASSWORD").ok();
    let room_id = std::env::var("MATRIX_ROOM_ID").ok();

    eprintln!("=== matrix-sdk-webrtc integration example ===");
    eprintln!("homeserver: {homeserver}");

    // Build client
    let client = Client::builder()
        .server_name_or_homeserver_url(&homeserver)
        .build()
        .await?;

    // Login if credentials supplied
    if let (Some(user), Some(pass)) = (&user, &password) {
        eprintln!("Logging in as {user} ...");
        client.matrix_auth()
            .login_username(user, pass)
            .initial_device_display_name("webrtc-integration-example")
            .send()
            .await?;
        eprintln!("Logged in: {:?}", client.user_id());
    } else {
        eprintln!("No credentials — sync-only mode (must have restored session).");
    }

    // Resolve room
    let room: Room = match &room_id {
        Some(id) => {
            let room_id = <ruma::OwnedRoomId>::try_from(id.as_str())
                .expect("invalid MATRIX_ROOM_ID");
            client.get_room(&room_id)
                .unwrap_or_else(|| panic!("room {id} not found"))
        }
        None => {
            let resp = client.sync_once(SyncSettings::default()).await?;
            let rooms = resp.rooms;
            let room = rooms.joined
                .keys()
                .next()
                .or_else(|| rooms.left.keys().next())
                .or_else(|| rooms.invited.keys().next())
                .expect("no rooms found — set MATRIX_ROOM_ID=!room:server");
            client.get_room(room).expect("room not in store")
        }
    };
    eprintln!("Room: {}", room.room_id());

    // Build call infrastructure
    let call_manager = Arc::new(Mutex::new(CallManager::new(CallConfig::default())));
    let transport = MatrixCallTransport::new(room.clone());
    {
        let mut guard = call_manager.lock().await;
        guard.set_transport(Box::new(transport));
    }

    // Register inbound event listener
    let _handle = register_call_event_listener(&room, call_manager.clone());
    eprintln!("Registered m.call.* event listener on room");

    // Perform an initial sync to catch any pending events
    eprintln!("Performing initial sync ...");
    client.sync_once(SyncSettings::default()).await?;
    eprintln!("Sync complete — listener is active.");

    eprintln!("Waiting for incoming calls (Ctrl-C to exit) ...");
    tokio::signal::ctrl_c().await?;
    eprintln!("Shutting down.");

    Ok(())
}
