pub mod http;
pub mod crypto;
pub mod storage;
pub mod console;

use rquickjs::Ctx;
use anyhow::Result;

/// 注册所有 JS 绑定
pub fn register_all(ctx: &Ctx<'_>) -> Result<()> {
    console::register(ctx)?;
    http::register(ctx)?;
    crypto::register(ctx)?;
    storage::register(ctx)?;
    Ok(())
}
