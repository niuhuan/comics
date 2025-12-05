use rquickjs::{Ctx, Function, Object};
use rquickjs::function::Rest;
use anyhow::Result;

/// 注册 console 对象
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    let console = Object::new(ctx.clone())?;
    
    // console.log
    console.set("log", Function::new(ctx.clone(), |args: Rest<String>| {
        let message = args.0.join(" ");
        tracing::info!("[JS] {}", message);
    })?)?;
    
    // console.error
    console.set("error", Function::new(ctx.clone(), |args: Rest<String>| {
        let message = args.0.join(" ");
        tracing::error!("[JS] {}", message);
    })?)?;
    
    // console.warn
    console.set("warn", Function::new(ctx.clone(), |args: Rest<String>| {
        let message = args.0.join(" ");
        tracing::warn!("[JS] {}", message);
    })?)?;
    
    // console.debug
    console.set("debug", Function::new(ctx.clone(), |args: Rest<String>| {
        let message = args.0.join(" ");
        tracing::debug!("[JS] {}", message);
    })?)?;
    
    globals.set("console", console)?;
    
    Ok(())
}
