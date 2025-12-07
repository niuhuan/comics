pub mod http;
pub mod crypto;
pub mod storage;
pub mod console;
pub mod html;

use rquickjs::{Ctx, Value};
use anyhow::Result;

/// 注册所有 JS 绑定
pub fn register_all(ctx: &Ctx<'_>) -> Result<()> {
    console::register(ctx)?;
    http::register(ctx)?;
    crypto::register(ctx)?;
    storage::register(ctx)?;
    html::register(ctx)?;
    
    // 创建 runtime 对象，作为模块的标准接口
    // 模块脚本使用 runtime.http.get, runtime.storage.get 等
    let runtime_obj = r#"
        const runtime = {
            http: http,
            storage: storage,
            crypto: __crypto__,
            console: console,
            html: __html__
        };
    "#;
    
    let _: Value = ctx.eval(runtime_obj)?;
    
    tracing::debug!("[JS Bindings] All bindings registered, runtime object created");
    
    Ok(())
}
