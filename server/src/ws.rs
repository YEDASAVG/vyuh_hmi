use axum::{
    extract::State,
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    response::Response,
};

use futures::{SinkExt, StreamExt};
use tracing::{info, warn};

use crate::state::AppState;

// Handler if anybody connect on /ws

pub async fn ws_handler(ws: WebSocketUpgrade, State(state): State<AppState>,) -> Response {
    info!("New Websocket connection request");
    ws.on_upgrade(move |socket| handle_socket(socket, state))
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