pub mod api;
mod frb_generated;
pub mod database;
pub mod js_engine;
pub mod modules;
pub mod http;
pub mod crypto;

use once_cell::sync::OnceCell;
use std::path::PathBuf;

/// 全局应用根目录
static ROOT_PATH: OnceCell<PathBuf> = OnceCell::new();

/// 数据库目录
static DATABASE_DIR: OnceCell<PathBuf> = OnceCell::new();

/// 模块目录
static MODULES_DIR: OnceCell<PathBuf> = OnceCell::new();

/// 缓存目录
static CACHE_DIR: OnceCell<PathBuf> = OnceCell::new();

/// 获取根目录
pub fn get_root_path() -> Option<&'static PathBuf> {
    ROOT_PATH.get()
}

/// 获取数据库目录
pub fn get_database_dir() -> Option<&'static PathBuf> {
    DATABASE_DIR.get()
}

/// 获取模块目录
pub fn get_modules_dir() -> Option<&'static PathBuf> {
    MODULES_DIR.get()
}

/// 获取缓存目录
pub fn get_cache_dir() -> Option<&'static PathBuf> {
    CACHE_DIR.get()
}

/// 初始化应用
pub async fn init_application(root: String) -> anyhow::Result<()> {
    // 初始化日志（只初始化一次）
    let _ = tracing_subscriber::fmt()
        .with_env_filter("info")
        .try_init();
    
    let root_path = PathBuf::from(&root);
    
    // 设置路径
    ROOT_PATH.set(root_path.clone()).map_err(|_| anyhow::anyhow!("Root path already set"))?;
    
    let db_dir = root_path.join("database");
    let modules_dir = root_path.join("modules");
    let cache_dir = root_path.join("cache");
    
    // 创建目录
    tokio::fs::create_dir_all(&db_dir).await?;
    tokio::fs::create_dir_all(&modules_dir).await?;
    tokio::fs::create_dir_all(&cache_dir).await?;
    
    DATABASE_DIR.set(db_dir.clone()).map_err(|_| anyhow::anyhow!("Database dir already set"))?;
    MODULES_DIR.set(modules_dir.clone()).map_err(|_| anyhow::anyhow!("Modules dir already set"))?;
    CACHE_DIR.set(cache_dir).map_err(|_| anyhow::anyhow!("Cache dir already set"))?;
    
    // 初始化数据库
    database::init_database(&db_dir).await?;
    
    // 初始化模块管理器
    api::module_api::init_module_manager(&modules_dir)?;
    
    // 初始化代理设置（从数据库加载）
    api::proxy_api::init_proxy().await?;
    
    tracing::info!("Application initialized at: {}", root);
    
    Ok(())
}
