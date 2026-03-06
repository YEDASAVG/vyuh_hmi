//! Library crate for integration tests.
//! Re-exports all public modules so tests can access `server::db`, `server::auth`, etc.

pub mod state;
pub mod models;
pub mod db;
pub mod auth;
pub mod config;
pub mod export;
pub mod rate_limit;
pub mod tsdb;
pub mod ws;
pub mod routes;
pub mod modbus;
pub mod opcua_client;
pub mod protocol;
pub mod discovery;
