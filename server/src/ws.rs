use axum::{
    extract::{Query, State},
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};

use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use tracing::{info, warn};

use crate::auth;
use crate::state::AppState;

#[derive(Deserialize)]
pub struct WsQuery {
    pub token: Option<String>,
}

// Handler for /ws — validates JWT from ?token= query param

pub async fn ws_handler(
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> Response {
    // Validate token from query parameter
    let token = match query.token {
        Some(t) => t,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": "Missing token query parameter" })),
            )
                .into_response();
        }
    };

    match auth::validate_token(&token) {
        Ok(claims) => {
            info!("WebSocket auth OK for user '{}'", claims.sub);
            ws.on_upgrade(move |socket| handle_socket(socket, state))
        }
        Err(e) => {
            warn!("WebSocket auth failed: {}", e);
            (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": e })),
            )
                .into_response()
        }
    }
}

// actual websocket logic

async fn handle_socket(socket: WebSocket, state: AppState){
    let (mut sender, mut receiver) = socket.split(); // split socket into two parts

    let mut rx = state.tx.subscribe(); // take receiver from boradcast channel

    info!("Websocket Client connected");

    // Task 1: send data from Broadcast -> client

    let mut send_task = tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            if sender.send(Message::Text(msg.into())).await.is_err() {
                break; // client disconnected
            }
        }
    });

    // Task 2: handle the message came from Client

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

    warn!("WebSocket client disconnected");
}