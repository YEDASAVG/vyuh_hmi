//! Phase 8: Authentication, RBAC & Audit Trail (21 CFR Part 11)
//!
//! - Users table with argon2 password hashing
//! - JWT token generation & validation
//! - Axum middleware for route protection
//! - Role-based access control (Viewer / Operator / Admin)
//! - Audit trail logging for every write/control action
//! - Electronic signature (re-auth) for critical operations

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum::{
    Json,
    extract::{Request, State},
    http::{HeaderMap, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Duration, Utc};
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;
use tracing::info;

// ── Constants ───────────────────────────────────────────────────

/// JWT secret — in production this would come from env/config.
const JWT_SECRET: &str = "vyuh-hmi-jwt-secret-2026-phase8";

/// Token expiry duration.
const TOKEN_EXPIRY_HOURS: i64 = 8;

// ── Data Types ──────────────────────────────────────────────────

/// User roles ordered by privilege level.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Viewer,   // read-only — dashboards, history
    Operator, // can write to PLC (agitator, batch control)
    Admin,    // manage users + all operator permissions
}

impl Role {
    pub fn from_str(s: &str) -> Self {
        match s {
            "admin" => Role::Admin,
            "operator" => Role::Operator,
            _ => Role::Viewer,
        }
    }

    #[allow(dead_code)]
    pub fn as_str(&self) -> &str {
        match self {
            Role::Admin => "admin",
            Role::Operator => "operator",
            Role::Viewer => "viewer",
        }
    }

    /// Check if role has at least the given permission level.
    pub fn has_permission(&self, required: &Role) -> bool {
        let level = |r: &Role| match r {
            Role::Viewer => 0,
            Role::Operator => 1,
            Role::Admin => 2,
        };
        level(self) >= level(required)
    }
}

/// JWT claims stored in the token.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,       // username
    pub role: String,      // "viewer" | "operator" | "admin"
    pub user_id: String,   // UUID
    pub exp: usize,        // expiry timestamp
    pub iat: usize,        // issued at
}

/// User record from the database.
#[derive(Debug, Clone, Serialize)]
pub struct User {
    pub id: String,
    pub username: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub role: String,
    pub created_at: String,
    pub is_active: bool,
}

/// Audit trail entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    pub id: i64,
    pub user_id: String,
    pub username: String,
    pub action: String,          // "write_register", "emergency_stop", "login", "add_device", etc.
    pub device_id: Option<String>,
    pub details: String,         // JSON with old_value, new_value, register, etc.
    pub timestamp: String,
    pub ip_address: Option<String>,
}

// ── Request / Response types ────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
#[allow(dead_code)]
pub struct LoginResponse {
    pub token: String,
    pub user: UserInfo,
    pub expires_at: String,
}

#[derive(Debug, Serialize)]
#[allow(dead_code)]
pub struct UserInfo {
    pub id: String,
    pub username: String,
    pub role: String,
}

#[derive(Debug, Deserialize)]
pub struct CreateUserRequest {
    pub username: String,
    pub password: String,
    pub role: String,    // "viewer" | "operator" | "admin"
}

#[derive(Debug, Deserialize)]
pub struct EsigRequest {
    pub username: String,
    pub password: String,
    pub reason: String,
}

#[derive(Debug, Deserialize)]
pub struct AuditQueryParams {
    pub user_id: Option<String>,
    pub device_id: Option<String>,
    pub action: Option<String>,
    pub limit: Option<i64>,
}

// ── Database Setup ──────────────────────────────────────────────

/// Create auth and audit tables. Called from db::init_db.
pub async fn init_auth_tables(pool: &SqlitePool) {
    // Users table
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'viewer',
            created_at TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1
        )"
    )
    .execute(pool)
    .await
    .expect("Failed to create users table");

    // Audit trail table
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS audit_trail (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            username TEXT NOT NULL,
            action TEXT NOT NULL,
            device_id TEXT,
            details TEXT NOT NULL DEFAULT '{}',
            timestamp TEXT NOT NULL,
            ip_address TEXT
        )"
    )
    .execute(pool)
    .await
    .expect("Failed to create audit_trail table");

    // Seed default admin user if no users exist
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users")
        .fetch_one(pool)
        .await
        .unwrap_or((0,));

    if count.0 == 0 {
        let admin_id = uuid::Uuid::new_v4().to_string();
        let hash = hash_password("admin123").expect("Failed to hash default password");
        let now = Utc::now().to_rfc3339();
        sqlx::query(
            "INSERT INTO users (id, username, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?)"
        )
        .bind(&admin_id)
        .bind("admin")
        .bind(&hash)
        .bind("admin")
        .bind(&now)
        .execute(pool)
        .await
        .ok();

        // Also create a default operator
        let op_id = uuid::Uuid::new_v4().to_string();
        let op_hash = hash_password("operator123").expect("Failed to hash default password");
        sqlx::query(
            "INSERT INTO users (id, username, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?)"
        )
        .bind(&op_id)
        .bind("operator")
        .bind(&op_hash)
        .bind("operator")
        .bind(&now)
        .execute(pool)
        .await
        .ok();

        // And a viewer
        let v_id = uuid::Uuid::new_v4().to_string();
        let v_hash = hash_password("viewer123").expect("Failed to hash default password");
        sqlx::query(
            "INSERT INTO users (id, username, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?)"
        )
        .bind(&v_id)
        .bind("viewer")
        .bind(&v_hash)
        .bind("viewer")
        .bind(&now)
        .execute(pool)
        .await
        .ok();

        info!("Seeded default users: admin/admin123, operator/operator123, viewer/viewer123");
    }
}

// ── Password Hashing ────────────────────────────────────────────

pub fn hash_password(password: &str) -> Result<String, String> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    argon2
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| format!("Hash failed: {e}"))
}

pub fn verify_password(password: &str, hash: &str) -> bool {
    let parsed = match PasswordHash::new(hash) {
        Ok(h) => h,
        Err(_) => return false,
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

// ── JWT ─────────────────────────────────────────────────────────

pub fn create_token(user_id: &str, username: &str, role: &str) -> Result<(String, DateTime<Utc>), String> {
    let expires_at = Utc::now() + Duration::hours(TOKEN_EXPIRY_HOURS);
    let claims = Claims {
        sub: username.to_string(),
        role: role.to_string(),
        user_id: user_id.to_string(),
        exp: expires_at.timestamp() as usize,
        iat: Utc::now().timestamp() as usize,
    };

    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .map_err(|e| format!("Token creation failed: {e}"))?;

    Ok((token, expires_at))
}

pub fn validate_token(token: &str) -> Result<Claims, String> {
    decode::<Claims>(
        token,
        &DecodingKey::from_secret(JWT_SECRET.as_bytes()),
        &Validation::default(),
    )
    .map(|data| data.claims)
    .map_err(|e| format!("Invalid token: {e}"))
}

// ── Axum Middleware ─────────────────────────────────────────────

/// Extract Bearer token from request headers.
fn extract_token(headers: &HeaderMap) -> Option<String> {
    headers
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .map(|t| t.to_string())
}

/// Auth middleware — validates JWT and injects Claims into request extensions.
/// Used on protected routes.
pub async fn auth_middleware(
    headers: HeaderMap,
    mut request: Request,
    next: Next,
) -> Response {
    let token = match extract_token(&headers) {
        Some(t) => t,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "success": false,
                    "error": "Missing Authorization header"
                })),
            )
                .into_response();
        }
    };

    match validate_token(&token) {
        Ok(claims) => {
            request.extensions_mut().insert(claims);
            next.run(request).await
        }
        Err(e) => (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "success": false,
                "error": e
            })),
        )
            .into_response(),
    }
}

/// Require at least Operator role.
pub async fn require_operator(
    headers: HeaderMap,
    mut request: Request,
    next: Next,
) -> Response {
    let token = match extract_token(&headers) {
        Some(t) => t,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": "Missing Authorization header" })),
            )
                .into_response();
        }
    };

    match validate_token(&token) {
        Ok(claims) => {
            let role = Role::from_str(&claims.role);
            if !role.has_permission(&Role::Operator) {
                return (
                    StatusCode::FORBIDDEN,
                    Json(serde_json::json!({ "success": false, "error": "Operator or Admin role required" })),
                )
                    .into_response();
            }
            request.extensions_mut().insert(claims);
            next.run(request).await
        }
        Err(e) => (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "success": false, "error": e })),
        )
            .into_response(),
    }
}

/// Require Admin role.
pub async fn require_admin(
    headers: HeaderMap,
    mut request: Request,
    next: Next,
) -> Response {
    let token = match extract_token(&headers) {
        Some(t) => t,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": "Missing Authorization header" })),
            )
                .into_response();
        }
    };

    match validate_token(&token) {
        Ok(claims) => {
            let role = Role::from_str(&claims.role);
            if !role.has_permission(&Role::Admin) {
                return (
                    StatusCode::FORBIDDEN,
                    Json(serde_json::json!({ "success": false, "error": "Admin role required" })),
                )
                    .into_response();
            }
            request.extensions_mut().insert(claims);
            next.run(request).await
        }
        Err(e) => (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "success": false, "error": e })),
        )
            .into_response(),
    }
}

// ── Auth Route Handlers ─────────────────────────────────────────

/// POST /api/auth/login
pub async fn login(
    State(state): State<crate::state::AppState>,
    Json(req): Json<LoginRequest>,
) -> Response {
    // Find user — query as individual columns to avoid bool deserialization issues
    let row = sqlx::query_as::<_, (String, String, String, String, String, i32)>(
        "SELECT id, username, password_hash, role, created_at, is_active FROM users WHERE username = ?"
    )
    .bind(&req.username)
    .fetch_optional(&state.db)
    .await;

    let row = match row {
        Ok(r) => r,
        Err(e) => {
            tracing::error!("Login query failed for '{}': {}", req.username, e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "Internal server error" })),
            )
                .into_response();
        }
    };

    let user = match row {
        Some((id, username, password_hash, role, created_at, is_active)) => {
            if is_active == 0 {
                return (
                    StatusCode::FORBIDDEN,
                    Json(serde_json::json!({ "success": false, "error": "Account disabled" })),
                )
                    .into_response();
            }
            User { id, username, password_hash, role, created_at, is_active: is_active != 0 }
        }
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": "Invalid credentials" })),
            )
                .into_response();
        }
    };

    // Verify password
    if !verify_password(&req.password, &user.password_hash) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "success": false, "error": "Invalid credentials" })),
        )
            .into_response();
    }

    // Generate token
    let (token, expires_at) = match create_token(&user.id, &user.username, &user.role) {
        Ok(t) => t,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": e })),
            )
                .into_response();
        }
    };

    // Log login to audit trail
    log_audit(
        &state.db,
        &user.id,
        &user.username,
        "login",
        None,
        "{}",
        None,
    )
    .await;

    info!("User '{}' logged in (role: {})", user.username, user.role);

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "success": true,
            "data": {
                "token": token,
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "role": user.role,
                },
                "expires_at": expires_at.to_rfc3339(),
            }
        })),
    )
        .into_response()
}

/// POST /api/auth/verify — check if token is still valid
pub async fn verify_token_handler(
    headers: HeaderMap,
) -> Response {
    let token = match extract_token(&headers) {
        Some(t) => t,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": "Missing token" })),
            )
                .into_response();
        }
    };

    match validate_token(&token) {
        Ok(claims) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "success": true,
                "data": {
                    "user_id": claims.user_id,
                    "username": claims.sub,
                    "role": claims.role,
                }
            })),
        )
            .into_response(),
        Err(e) => (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "success": false, "error": e })),
        )
            .into_response(),
    }
}

/// POST /api/auth/esig — electronic signature (re-authenticate for critical actions)
pub async fn electronic_signature(
    State(state): State<crate::state::AppState>,
    Json(req): Json<EsigRequest>,
) -> Response {
    let user = sqlx::query_as::<_, (String, String, String, String)>(
        "SELECT id, username, password_hash, role FROM users WHERE username = ? AND is_active = 1"
    )
    .bind(&req.username)
    .fetch_optional(&state.db)
    .await;

    let user = match user {
        Ok(r) => r,
        Err(e) => {
            tracing::error!("E-signature query failed for '{}': {}", req.username, e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": "Internal server error" })),
            )
                .into_response();
        }
    };

    let (user_id, username, password_hash, role) = match user {
        Some(u) => u,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({ "success": false, "error": "Invalid credentials" })),
            )
                .into_response();
        }
    };

    if !verify_password(&req.password, &password_hash) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({ "success": false, "error": "Invalid credentials" })),
        )
            .into_response();
    }

    // Log e-signature to audit trail
    let details = serde_json::json!({ "reason": req.reason }).to_string();
    log_audit(
        &state.db,
        &user_id,
        &username,
        "electronic_signature",
        None,
        &details,
        None,
    )
    .await;

    info!("E-signature verified for '{}': {}", username, req.reason);

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "success": true,
            "data": {
                "verified": true,
                "user_id": user_id,
                "username": username,
                "role": role,
                "reason": req.reason,
            }
        })),
    )
        .into_response()
}

/// GET /api/users — list all users (admin only)
pub async fn list_users(
    State(state): State<crate::state::AppState>,
) -> Response {
    let users = sqlx::query_as::<_, (String, String, String, String, i32)>(
        "SELECT id, username, role, created_at, is_active FROM users ORDER BY created_at"
    )
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let user_list: Vec<serde_json::Value> = users
        .into_iter()
        .map(|(id, username, role, created_at, is_active)| {
            serde_json::json!({
                "id": id,
                "username": username,
                "role": role,
                "created_at": created_at,
                "is_active": is_active != 0,
            })
        })
        .collect();

    (
        StatusCode::OK,
        Json(serde_json::json!({ "success": true, "data": user_list })),
    )
        .into_response()
}

/// POST /api/users — create a new user (admin only)
pub async fn create_user(
    State(state): State<crate::state::AppState>,
    request: Request,
) -> Response {
    // Get the admin's claims from middleware
    let claims = request.extensions().get::<Claims>().cloned();

    // Parse body manually since we already consumed the request in middleware
    let body = match axum::body::to_bytes(request.into_body(), 1024 * 16).await {
        Ok(b) => b,
        Err(_) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "success": false, "error": "Invalid request body" })),
            )
                .into_response();
        }
    };

    let req: CreateUserRequest = match serde_json::from_slice(&body) {
        Ok(r) => r,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({ "success": false, "error": format!("Invalid JSON: {e}") })),
            )
                .into_response();
        }
    };

    // Validate role
    if !["viewer", "operator", "admin"].contains(&req.role.as_str()) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "success": false, "error": "Role must be viewer, operator, or admin" })),
        )
            .into_response();
    }

    // Hash password
    let hash = match hash_password(&req.password) {
        Ok(h) => h,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({ "success": false, "error": e })),
            )
                .into_response();
        }
    };

    let user_id = uuid::Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();

    let result = sqlx::query(
        "INSERT INTO users (id, username, password_hash, role, created_at) VALUES (?, ?, ?, ?, ?)"
    )
    .bind(&user_id)
    .bind(&req.username)
    .bind(&hash)
    .bind(&req.role)
    .bind(&now)
    .execute(&state.db)
    .await;

    match result {
        Ok(_) => {
            // Audit log
            if let Some(claims) = claims {
                let details = serde_json::json!({
                    "created_user": req.username,
                    "role": req.role,
                })
                .to_string();
                log_audit(&state.db, &claims.user_id, &claims.sub, "create_user", None, &details, None).await;
            }

            info!("User '{}' created (role: {})", req.username, req.role);

            (
                StatusCode::CREATED,
                Json(serde_json::json!({
                    "success": true,
                    "data": {
                        "id": user_id,
                        "username": req.username,
                        "role": req.role,
                    }
                })),
            )
                .into_response()
        }
        Err(e) => {
            let msg = if e.to_string().contains("UNIQUE") {
                format!("Username '{}' already exists", req.username)
            } else {
                format!("Failed to create user: {e}")
            };
            (
                StatusCode::CONFLICT,
                Json(serde_json::json!({ "success": false, "error": msg })),
            )
                .into_response()
        }
    }
}

// ── Audit Trail ─────────────────────────────────────────────────

/// Log an action to the audit trail.
pub async fn log_audit(
    pool: &SqlitePool,
    user_id: &str,
    username: &str,
    action: &str,
    device_id: Option<&str>,
    details: &str,
    ip_address: Option<&str>,
) {
    let now = Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO audit_trail (user_id, username, action, device_id, details, timestamp, ip_address)
         VALUES (?, ?, ?, ?, ?, ?, ?)"
    )
    .bind(user_id)
    .bind(username)
    .bind(action)
    .bind(device_id)
    .bind(details)
    .bind(&now)
    .bind(ip_address)
    .execute(pool)
    .await
    .ok();
}

/// GET /api/audit — query audit trail with filters
pub async fn get_audit_trail(
    State(state): State<crate::state::AppState>,
    axum::extract::Query(params): axum::extract::Query<AuditQueryParams>,
) -> Response {
    let limit = params.limit.unwrap_or(100);

    // Build dynamic query based on filters
    let (query, _binds) = build_audit_query(&params, limit);
    
    // We use a simple approach: fetch all, filter in Rust
    // (SQLite is fast enough for audit trail sizes)
    let rows = sqlx::query_as::<_, (i64, String, String, String, Option<String>, String, String, Option<String>)>(
        &query
    );

    // Bind parameters based on which filters are present
    let rows = if let Some(ref uid) = params.user_id {
        if let Some(ref did) = params.device_id {
            if let Some(ref act) = params.action {
                rows.bind(uid).bind(did).bind(act).bind(limit)
            } else {
                rows.bind(uid).bind(did).bind(limit)
            }
        } else if let Some(ref act) = params.action {
            rows.bind(uid).bind(act).bind(limit)
        } else {
            rows.bind(uid).bind(limit)
        }
    } else if let Some(ref did) = params.device_id {
        if let Some(ref act) = params.action {
            rows.bind(did).bind(act).bind(limit)
        } else {
            rows.bind(did).bind(limit)
        }
    } else if let Some(ref act) = params.action {
        rows.bind(act).bind(limit)
    } else {
        rows.bind(limit)
    };

    let entries = rows
        .fetch_all(&state.db)
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|(id, user_id, username, action, device_id, details, timestamp, ip_address)| {
            AuditEntry { id, user_id, username, action, device_id, details, timestamp, ip_address }
        })
        .collect::<Vec<_>>();

    (
        StatusCode::OK,
        Json(serde_json::json!({ "success": true, "data": entries })),
    )
        .into_response()
}

/// Build SQL query string for audit trail with optional filters.
fn build_audit_query(params: &AuditQueryParams, _limit: i64) -> (String, Vec<String>) {
    let mut conditions = Vec::new();
    let mut binds = Vec::new();

    if let Some(ref uid) = params.user_id {
        conditions.push("user_id = ?".to_string());
        binds.push(uid.clone());
    }
    if let Some(ref did) = params.device_id {
        conditions.push("device_id = ?".to_string());
        binds.push(did.clone());
    }
    if let Some(ref act) = params.action {
        conditions.push("action = ?".to_string());
        binds.push(act.clone());
    }

    let where_clause = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };

    let query = format!(
        "SELECT id, user_id, username, action, device_id, details, timestamp, ip_address
         FROM audit_trail {} ORDER BY id DESC LIMIT ?",
        where_clause
    );

    (query, binds)
}
