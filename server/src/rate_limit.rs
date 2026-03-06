//! Phase 10.5: Rate Limiting — token-bucket per IP for production resilience.
//!
//! Simple in-memory rate limiter. For a distributed setup, use Redis.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
};
use tokio::sync::Mutex;

/// Per-IP rate limit state.
#[derive(Clone)]
struct Bucket {
    tokens: f64,
    last_refill: Instant,
}

/// Rate limiter configuration.
#[derive(Clone)]
pub struct RateLimiter {
    buckets: Arc<Mutex<HashMap<String, Bucket>>>,
    /// Max tokens (burst size).
    max_tokens: f64,
    /// Tokens refilled per second.
    refill_rate: f64,
}

impl RateLimiter {
    /// Create a new rate limiter.
    /// - `max_tokens`: burst capacity (e.g., 100)
    /// - `refill_rate`: tokens/sec (e.g., 10 = 10 req/sec sustained)
    pub fn new(max_tokens: f64, refill_rate: f64) -> Self {
        Self {
            buckets: Arc::new(Mutex::new(HashMap::new())),
            max_tokens,
            refill_rate,
        }
    }

    /// Check if a request from this IP is allowed.
    async fn check(&self, ip: &str) -> bool {
        let mut buckets = self.buckets.lock().await;
        let now = Instant::now();

        let bucket = buckets.entry(ip.to_string()).or_insert(Bucket {
            tokens: self.max_tokens,
            last_refill: now,
        });

        // Refill tokens based on elapsed time
        let elapsed = now.duration_since(bucket.last_refill).as_secs_f64();
        bucket.tokens = (bucket.tokens + elapsed * self.refill_rate).min(self.max_tokens);
        bucket.last_refill = now;

        if bucket.tokens >= 1.0 {
            bucket.tokens -= 1.0;
            true
        } else {
            false
        }
    }

    /// Periodically clean up expired buckets (call from background task).
    pub async fn cleanup(&self) {
        let mut buckets = self.buckets.lock().await;
        let now = Instant::now();
        buckets.retain(|_, b| now.duration_since(b.last_refill).as_secs() < 300);
    }
}

/// Axum middleware that rate-limits by client IP.
pub async fn rate_limit_middleware(
    req: Request,
    next: Next,
) -> Response {
    // Extract client IP from headers or connection
    let ip = req
        .headers()
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.split(',').next().unwrap_or("unknown").trim().to_string())
        .or_else(|| {
            req.extensions()
                .get::<axum::extract::ConnectInfo<std::net::SocketAddr>>()
                .map(|ci| ci.0.ip().to_string())
        })
        .unwrap_or_else(|| "unknown".to_string());

    // Use a global rate limiter stored in extensions
    // For simplicity, we use a static approach
    static LIMITER: std::sync::OnceLock<RateLimiter> = std::sync::OnceLock::new();
    let limiter = LIMITER.get_or_init(|| RateLimiter::new(100.0, 20.0)); // 100 burst, 20/sec

    if !limiter.check(&ip).await {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            [("retry-after", "5")],
            "Rate limit exceeded. Try again in a few seconds.",
        )
            .into_response();
    }

    next.run(req).await
}
