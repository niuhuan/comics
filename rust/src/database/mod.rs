pub mod connection;
pub mod entities;
pub mod migration;

use std::path::Path;
use sea_orm::DatabaseConnection;
use once_cell::sync::OnceCell;
use tokio::sync::RwLock;

static DATABASE: OnceCell<RwLock<DatabaseConnection>> = OnceCell::new();

pub async fn init_database(db_dir: &Path) -> anyhow::Result<()> {
    let db_path = db_dir.join("comics.db");
    let conn = connection::connect(&db_path).await?;
    
    // 运行迁移
    migration::run_migrations(&conn).await?;
    
    DATABASE.set(RwLock::new(conn))
        .map_err(|_| anyhow::anyhow!("Database already initialized"))?;
    
    tracing::info!("Database initialized at: {:?}", db_path);
    
    Ok(())
}

pub fn get_database() -> Option<&'static RwLock<DatabaseConnection>> {
    DATABASE.get()
}

pub async fn get_db_conn() -> anyhow::Result<tokio::sync::RwLockReadGuard<'static, DatabaseConnection>> {
    get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))
        .map(|db| db.blocking_read())
}
