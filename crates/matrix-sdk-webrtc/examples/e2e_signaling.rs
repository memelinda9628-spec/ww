//! E2E signaling test 鈥?stdin/stdout JSON-line protocol.
//!
//! Usage: cargo run -p matrix-sdk-webrtc --features webrtc --example e2e_signaling -- [offerer|answerer]
//!
//! Each line on stdin/stdout is one JSON object: {"type":"offer"|"answer"|"ice"|"done","sdp":"...","candidate":"...",...}

use std::io::{self, Write};

use matrix_sdk_webrtc::{
    CallConfig,
    connection::{PeerConnection, SignalingMessage, PeerConnectionState},
};
use serde::{Deserialize, Serialize};
use tokio::io::AsyncBufReadExt;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "type")]
enum Msg {
    #[serde(rename = "offer")]
    Offer { sdp: String },
    #[serde(rename = "answer")]
    Answer { sdp: String },
    #[serde(rename = "ice")]
    Ice {
        candidate: String,
        #[serde(default)]
        sdp_mid: Option<String>,
        #[serde(default)]
        sdp_mline_index: Option<u16>,
    },
    #[serde(rename = "done")]
    Done,
    #[serde(rename = "connected")]
    Connected,
    #[serde(rename = "error")]
    Error { msg: String },
}

fn emit(msg: &Msg) {
    let json = serde_json::to_string(msg).unwrap();
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "{}", json).unwrap();
    stdout.flush().unwrap();
}

async fn read_stdin_line() -> Result<String, Box<dyn std::error::Error>> {
    let mut line = String::new();
    let mut reader = tokio::io::BufReader::new(tokio::io::stdin());
    reader.read_line(&mut line).await?;
    Ok(line)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let role = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: e2e_signaling [offerer|answerer]");
        std::process::exit(1);
    });

    eprintln!("[e2e_{}] started", role);

    matrix_sdk_webrtc::ensure_crypto_provider();

    // No STUN 鈥?host candidates only, for same-machine testing.
    let config = CallConfig {
        ice_servers: vec![],
        ..CallConfig::default()
    };

    match role.as_str() {
        "offerer" => run_offerer(config).await,
        "answerer" => run_answerer(config).await,
        _ => Err(format!("unknown role: {}", role).into()),
    }
}

async fn run_offerer(config: CallConfig) -> Result<(), Box<dyn std::error::Error>> {
    let pc = PeerConnection::new(&config).await?;
    let mut signaling_rx = pc.take_signaling_receiver().unwrap();

    // Step 1: create data channel to trigger ICE ufrag/pwd init,
    // then create and emit offer
    pc.create_data_channel("e2e").await?;
    let offer = pc.create_offer().await?;
    emit(&Msg::Offer { sdp: offer.sdp });
    eprintln!("[offerer] offer emitted");

    // Step 2: read answer from stdin
    let line = read_stdin_line().await?;
    let msg: Msg = serde_json::from_str(line.trim())?;
    let answer_sdp = match msg {
        Msg::Answer { sdp } => {
            webrtc::peer_connection::sdp::session_description::RTCSessionDescription::answer(sdp)?
        }
        _ => {
            emit(&Msg::Error { msg: "expected answer".into() });
            return Err("expected answer".into());
        }
    };
    pc.set_remote_description(answer_sdp).await?;
    eprintln!("[offerer] remote description set");

    // Step 3: exchange ICE candidates
    exchange_ice("offerer", &pc, &mut signaling_rx).await?;

    // Step 4: wait for connected
    wait_connected("offerer", &pc).await;

    eprintln!("[offerer] done");
    Ok(())
}

async fn run_answerer(config: CallConfig) -> Result<(), Box<dyn std::error::Error>> {
    // Step 1: read offer from stdin
    let line = read_stdin_line().await?;
    let msg: Msg = serde_json::from_str(line.trim())?;
    let offer_sdp = match msg {
        Msg::Offer { sdp } => {
            webrtc::peer_connection::sdp::session_description::RTCSessionDescription::offer(sdp)?
        }
        _ => {
            emit(&Msg::Error { msg: "expected offer".into() });
            return Err("expected offer".into());
        }
    };

    let pc = PeerConnection::new_with_offer(&config, offer_sdp).await?;
    let mut signaling_rx = pc.take_signaling_receiver().unwrap();

    // Step 2: also create data channel before answer (mirrors loopback test)
    pc.create_data_channel("e2e").await?;
    let answer = pc.create_answer().await?;
    emit(&Msg::Answer { sdp: answer.sdp });
    eprintln!("[answerer] answer emitted");

    // Step 3: exchange ICE candidates
    exchange_ice("answerer", &pc, &mut signaling_rx).await?;

    // Step 4: wait for connected
    wait_connected("answerer", &pc).await;

    eprintln!("[answerer] done");
    Ok(())
}

async fn exchange_ice(
    tag: &str,
    pc: &PeerConnection,
    rx: &mut tokio::sync::mpsc::Receiver<SignalingMessage>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut local_done = false;
    let mut remote_done = false;
    let gather_timeout = tokio::time::Duration::from_secs(3);

    // Spawn a task to read stdin lines (remote ICE candidates)
    let mut stdin_lines = {
        let (tx, mut rx_line) = tokio::sync::mpsc::channel::<String>(32);
        tokio::spawn(async move {
            let mut reader = tokio::io::BufReader::new(tokio::io::stdin());
            let mut line = String::new();
            loop {
                line.clear();
                match reader.read_line(&mut line).await {
                    Ok(0) => break,
                    Ok(_) => {
                        if tx.send(line.clone()).await.is_err() {
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
        });
        rx_line
    };

    loop {
        tokio::select! {
            local = rx.recv() => {
                match local {
                    Some(SignalingMessage::IceCandidate(c)) => {
                        match c.to_json() {
                            Ok(init) => {
                                emit(&Msg::Ice {
                                    candidate: init.candidate,
                                    sdp_mid: init.sdp_mid,
                                    sdp_mline_index: init.sdp_mline_index,
                                });
                                eprintln!("[{}_ice] local candidate sent", tag);
                            }
                            Err(e) => {
                                eprintln!("[{}_ice] to_json failed: {}", tag, e);
                            }
                        }
                    }
                    Some(_) => {}
                    None => {
                        if !local_done {
                            local_done = true;
                            emit(&Msg::Done);
                            eprintln!("[{}_ice] local gathering done (channel closed)", tag);
                        }
                    }
                }
            }
            line = stdin_lines.recv() => {
                match line {
                    Some(line) => {
                        let line = line.trim().to_string();
                        if line.is_empty() { continue; }
                        let msg: Msg = match serde_json::from_str(&line) {
                            Ok(m) => m,
                            Err(e) => {
                                eprintln!("[{}_ice] parse error: {} for line: {}", tag, e, line);
                                continue;
                            }
                        };
                        match msg {
                            Msg::Ice { candidate, sdp_mid, sdp_mline_index } => {
                                let ice = RTCIceCandidateInit {
                                    candidate,
                                    sdp_mid,
                                    sdp_mline_index,
                                    username_fragment: None,
                                };
                                pc.add_ice_candidate_init(ice).await?;
                                eprintln!("[{}_ice] remote candidate added", tag);
                            }
                            Msg::Done => {
                                remote_done = true;
                                eprintln!("[{}_ice] remote gathering done", tag);
                            }
                            _ => {}
                        }
                    }
                    None => {
                        remote_done = true;
                        eprintln!("[{}_ice] stdin closed", tag);
                    }
                }
            }
            _ = tokio::time::sleep(gather_timeout) => {
                if !local_done {
                    local_done = true;
                    emit(&Msg::Done);
                    eprintln!("[{}_ice] local gathering done (timeout)", tag);
                }
            }
        }

        if local_done && remote_done {
            break;
        }
    }

    Ok(())
}

async fn wait_connected(tag: &str, pc: &PeerConnection) {
    let mut last_state = PeerConnectionState::New;
    for i in 0..120 {
        let state = pc.connection_state();
        if state != last_state {
            eprintln!("[{}_state] {:?} -> {:?}", tag, last_state, state);
            last_state = state;
        }
        match state {
            PeerConnectionState::Connected => {
                emit(&Msg::Connected);
                eprintln!("[{}] CONNECTED!", tag);
                return;
            }
            PeerConnectionState::Failed | PeerConnectionState::Disconnected => {
                emit(&Msg::Error { msg: format!("connection {:?}", state) });
                eprintln!("[{}] connection failed: {:?}", tag, state);
                return;
            }
            _ => {
                tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
            }
        }
        if i > 0 && i % 20 == 0 {
            eprintln!("[{}_state] still {:?} after {}s", tag, state, i/2);
        }
    }
    emit(&Msg::Error { msg: "timeout waiting for connection".into() });
    eprintln!("[{}] timeout", tag);
}

