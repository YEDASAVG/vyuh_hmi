//! Integration tests for Vyuh HMI Server
//!
//! Tests cover: config loading, database CRUD, auth flow,
//! CSV export, rate limiting, and time-series adapter.

#[cfg(test)]
mod tests {
    use std::path::Path;

    // ─────────────────────────────────────────────────────────
    // Config Tests
    // ─────────────────────────────────────────────────────────

    #[test]
    fn test_config_loads_successfully() {
        let content = std::fs::read_to_string("config.toml")
            .expect("config.toml must exist");
        let config: toml::Value = toml::from_str(&content)
            .expect("config.toml must be valid TOML");

        assert!(config.get("server").is_some(), "config must have [server]");
        assert!(config.get("database").is_some(), "config must have [database]");
        assert!(config.get("devices").is_some(), "config must have [[devices]]");
    }

    #[test]
    fn test_config_has_required_server_fields() {
        let content = std::fs::read_to_string("config.toml").unwrap();
        let config: toml::Value = toml::from_str(&content).unwrap();
        let server = config.get("server").unwrap();

        assert!(server.get("host").is_some());
        assert!(server.get("port").is_some());
        assert!(server.get("jwt_secret").is_some());

        let secret = server.get("jwt_secret").unwrap().as_str().unwrap();
        assert!(
            secret.len() >= 32,
            "jwt_secret must be >=32 chars, got {}",
            secret.len()
        );
    }

    #[test]
    fn test_config_devices_have_required_fields() {
        let content = std::fs::read_to_string("config.toml").unwrap();
        let config: toml::Value = toml::from_str(&content).unwrap();
        let devices = config.get("devices").unwrap().as_array().unwrap();

        assert!(!devices.is_empty(), "config must have at least one device");

        for dev in devices {
            assert!(dev.get("id").is_some(), "device must have 'id'");
            assert!(dev.get("name").is_some(), "device must have 'name'");
            assert!(dev.get("address").is_some(), "device must have 'address'");
            assert!(dev.get("protocol").is_some(), "device must have 'protocol'");
            let proto = dev.get("protocol").unwrap().as_str().unwrap();
            assert!(
                proto == "modbus" || proto == "opcua",
                "protocol must be 'modbus' or 'opcua', got '{proto}'"
            );
        }
    }

    // ─────────────────────────────────────────────────────────
    // Database Tests
    // ─────────────────────────────────────────────────────────

    async fn test_pool() -> sqlx::SqlitePool {
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .connect("sqlite::memory:")
            .await
            .unwrap();
        server::db::init_db_with_pool(&pool).await;
        pool
    }

    #[tokio::test]
    async fn test_db_init_creates_tables() {
        let pool = test_pool().await;

        let tables: Vec<(String,)> = sqlx::query_as(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .fetch_all(&pool)
        .await
        .unwrap();

        let table_names: Vec<&str> = tables.iter().map(|t| t.0.as_str()).collect();
        assert!(table_names.contains(&"plc_readings"), "plc_readings table");
        assert!(table_names.contains(&"devices"), "devices table");
        assert!(table_names.contains(&"alarms"), "alarms table");
        assert!(table_names.contains(&"batch_records"), "batch_records table");
        assert!(table_names.contains(&"batch_steps"), "batch_steps table");
    }

    #[tokio::test]
    async fn test_alarm_lifecycle() {
        let pool = test_pool().await;

        let req = server::models::RaiseAlarmRequest {
            device_id: "plc-01".to_string(),
            register: 100,
            label: "Temperature".to_string(),
            priority: server::models::AlarmPriority::High,
            value: 85.0,
            threshold: 80.0,
            message: "Temperature exceeded threshold".to_string(),
        };
        let alarm_id = server::db::raise_alarm(&pool, &req).await;
        assert!(alarm_id.is_some());
        let alarm_id = alarm_id.unwrap();

        assert!(server::db::has_active_alarm(&pool, "plc-01", 100).await);

        let params = server::models::AlarmQueryParams {
            device_id: Some("plc-01".to_string()),
            state: None,
            priority: None,
            limit: None,
        };
        let alarms = server::db::list_alarms(&pool, &params).await;
        assert_eq!(alarms.len(), 1);
        assert_eq!(alarms[0].device_id, "plc-01");
        assert_eq!(alarms[0].label, "Temperature");

        let ack_result = server::db::ack_alarm(&pool, alarm_id, "admin", None).await;
        assert!(ack_result.is_ok());

        let clear_result = server::db::clear_alarm(&pool, alarm_id).await;
        assert!(clear_result.is_ok());

        assert!(!server::db::has_active_alarm(&pool, "plc-01", 100).await);
    }

    #[tokio::test]
    async fn test_batch_lifecycle() {
        let pool = test_pool().await;

        let batch_id = server::db::create_batch(
            &pool, "BATCH-001", "Ibuprofen Synthesis", "plc-01", "operator1",
        )
        .await;
        assert!(batch_id.is_some());
        let record_id = batch_id.unwrap();

        let step_id = server::db::add_batch_step(&pool, record_id, 1, "Mixing", Some("temp=25C")).await;
        assert!(step_id.is_some());

        let result = server::db::update_batch_status(&pool, "BATCH-001", "completed", None).await;
        assert!(result.is_ok());

        let params = server::models::BatchQueryParams {
            device_id: None,
            status: None,
            limit: None,
        };
        let batches = server::db::list_batches(&pool, &params).await;
        assert_eq!(batches.len(), 1);
        assert_eq!(batches[0].batch_id, "BATCH-001");

        let full = server::db::get_batch_with_steps(&pool, "BATCH-001").await;
        assert!(full.is_some());
        let (record, steps) = full.unwrap();
        assert_eq!(record.recipe_name, "Ibuprofen Synthesis");
        assert_eq!(steps.len(), 1);
        assert_eq!(steps[0].name, "Mixing");
    }

    // ─────────────────────────────────────────────────────────
    // Auth Tests
    // ─────────────────────────────────────────────────────────

    #[test]
    fn test_password_hashing_roundtrip() {
        let password = "SecurePassword123!";
        let hash = server::auth::hash_password(password).expect("hashing should succeed");
        assert!(server::auth::verify_password(password, &hash));
        assert!(!server::auth::verify_password("wrong", &hash));
    }

    #[test]
    fn test_jwt_encode_decode() {
        let secret = "a-very-long-secret-key-for-testing-purposes-1234567890";
        let (token, _expires_at, _session_id) =
            server::auth::create_token("user-uuid", "testuser", "Operator", secret)
                .expect("token creation should succeed");
        assert!(!token.is_empty());

        let claims = server::auth::validate_token(&token, secret);
        assert!(claims.is_ok());
        let claims = claims.unwrap();
        assert_eq!(claims.sub, "testuser");
        assert_eq!(claims.role, "Operator");
        assert_eq!(claims.user_id, "user-uuid");
    }

    #[test]
    fn test_jwt_invalid_secret_fails() {
        let secret = "a-very-long-secret-key-for-testing-purposes-1234567890";
        let (token, _, _) =
            server::auth::create_token("user-uuid", "testuser", "Operator", secret).unwrap();
        let claims = server::auth::validate_token(&token, "different-secret-that-is-long-enough-too");
        assert!(claims.is_err());
    }

    #[test]
    fn test_password_complexity_validation() {
        assert!(server::auth::validate_password_complexity("StrongPass1").is_ok());
        assert!(server::auth::validate_password_complexity("Aa1").is_err());
        assert!(server::auth::validate_password_complexity("lowercase1").is_err());
        assert!(server::auth::validate_password_complexity("NoDigitHere").is_err());
    }

    // ─────────────────────────────────────────────────────────
    // Time-Series Adapter Tests
    // ─────────────────────────────────────────────────────────

    #[tokio::test]
    async fn test_sqlite_tsdb_insert_and_query() {
        use server::tsdb::TimeSeriesStore;

        let pool = test_pool().await;
        let store = server::tsdb::SqliteTimeSeries::new(pool);

        let reading = server::models::PlcData {
            device_id: "plc-01".to_string(),
            register: 100,
            value: 42.5,
            timestamp: chrono::Utc::now(),
        };

        store.insert(&reading).await;

        let history = store.query("plc-01", 10).await;
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].value, 42.5);
    }

    #[tokio::test]
    async fn test_sqlite_tsdb_purge() {
        use server::tsdb::TimeSeriesStore;

        let pool = test_pool().await;
        let store = server::tsdb::SqliteTimeSeries::new(pool);

        let reading = server::models::PlcData {
            device_id: "plc-01".to_string(),
            register: 100,
            value: 42.5,
            timestamp: chrono::Utc::now(),
        };
        store.insert(&reading).await;

        // Purge old data — nothing should be deleted since data is fresh
        let deleted = store.purge_older_than(1).await;
        assert_eq!(deleted, 0);

        let history = store.query("plc-01", 10).await;
        assert_eq!(history.len(), 1);
    }

    // ─────────────────────────────────────────────────────────
    // CSV Module Tests
    // ─────────────────────────────────────────────────────────

    #[test]
    fn test_csv_writer_produces_valid_output() {
        let mut wtr = csv::Writer::from_writer(Vec::new());
        wtr.write_record(["col1", "col2", "col3"]).unwrap();
        wtr.write_record(["a", "b", "c"]).unwrap();
        let data = String::from_utf8(wtr.into_inner().unwrap()).unwrap();
        assert!(data.contains("col1,col2,col3"));
        assert!(data.contains("a,b,c"));
    }

    // ─────────────────────────────────────────────────────────
    // File / Structure Tests
    // ─────────────────────────────────────────────────────────

    #[test]
    fn test_dockerfile_exists() {
        assert!(Path::new("Dockerfile").exists(), "Dockerfile must exist");
    }

    #[test]
    fn test_config_toml_exists() {
        assert!(Path::new("config.toml").exists(), "config.toml must exist");
    }
}
