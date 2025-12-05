use std::path::Path;
use sea_orm::{Database, DatabaseConnection, ConnectOptions};
use std::time::Duration;

pub async fn connect(db_path: &Path) -> anyhow::Result<DatabaseConnection> {
    let db_url = format!("sqlite:{}?mode=rwc", db_path.display());
    
    let mut opt = ConnectOptions::new(&db_url);
    opt.max_connections(10)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(10))
        .idle_timeout(Duration::from_secs(300))
        .sqlx_logging(false);
    
    let conn = Database::connect(opt).await?;
    
    tracing::info!("Database connected: {}", db_url);
    
    Ok(conn)
}
