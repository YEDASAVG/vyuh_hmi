use axum::{
    extract::State,
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    response::Response,
};

use futures::{SinkExt, StreamExt};
use tracing::{info, warn};

use crate::auth;
use crate::state::AppState;

/// Handler for /ws — accepts upgrade unconditionally, then authenticates
/// via the first message (which must be the JWT token).
///
/// This avoids leaking the token in the URL / access logs.
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> Response {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

/// Actual WebSocket logic — first-message auth, then broadcast data.
async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut sender, mut receiver) = socket.split();

    // ── Step 1: Wait for the first message to be the auth token ──
    let claims = loop {
        match tokio::time::timeout(std::time::Duration::from_secs(10), receiver.next()).await {
            Ok(Some(Ok(Message::Text(text)))) => {
                let token = text.trim().to_string();
                match auth::validate_token(&token, &state.jwt_secret) {
                    Ok(c) => {
                        // Verify session is still valid
                        if let Some(ref sid) = c.session_id {
                            if !auth::is_session_valid(&state, sid).await {
                                warn!("WebSocket auth failed — session revoked");
                                let _ = sender.send(Message::Text(
                                    r#"{"error":"session_revoked"}"#.into(),
                                )).await;
                                return;
                            }
                        }
                        // Send auth OK acknowledgement
                        let _ = sender.send(Message::Text(
                            r#"{"auth":"ok"}"#.into(),
                        )).await;
                        break c;
                    }
                    Err(e) => {
                        warn!("WebSocket auth failed: {}", e);
                        let _ = sender.send(Message::Text(
                            format!(r#"{{"error":"auth_failed","detail":"{}"}}"#, e).into(),
                        )).await;
                        return;
                    }
                }
            }
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) => {
                warn!("WebSocket closed before auth");
                return;
            }
            Err(_) => {
                warn!("WebSocket auth timed out (10s)");
                let _ = sender.send(Message::Text(
                    r#"{"error":"auth_timeout"}"#.into(),
                )).await;
                return;
            }
            _ => continue, // skip ping/pong/binary
        }
    };

    info!("WebSocket authenticated for user '{}'", claims.sub);

    // ── Step 2: Normal broadcast loop ──
    let mut rx = state.tx.subscribe();

    let mut send_task = tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(msg) => {
                    if sender.send(Message::Text(msg.into())).await.is_err() {
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    warn!("WebSocket receiver lagged, skipped {} messages", n);
                    continue; // recover — keep receiving
                }
                Err(_) => break, // channel closed
            }
        }
    });

    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Text(text) => {
                    info!("Received from client: {}", text);
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    tokio::select! {
        _ = &mut send_task => recv_task.abort(),
        _ = &mut recv_task => send_task.abort(),
    }

    warn!("WebSocket client disconnected (user: {})", claims.sub);
}