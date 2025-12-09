use rquickjs::{Ctx, Function, Object, Value};
use rquickjs::function::Rest;
use anyhow::Result;

/// 注册 console 对象
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    let console = Object::new(ctx.clone())?;
    
    // console.log - 使用 info 级别，更容易看到
    console.set("log", Function::new(ctx.clone(), |args: Rest<Value>| {
        let message: String = args.0.iter()
            .map(|v| {
                // 尝试直接转换为字符串
                if let Ok(s) = v.get::<String>() {
                    s
                } else if let Ok(n) = v.get::<f64>() {
                    if n.fract() == 0.0 {
                        format!("{}", n as i64)
                    } else {
                        format!("{}", n)
                    }
                } else if let Ok(b) = v.get::<bool>() {
                    b.to_string()
                } else if v.is_null() {
                    "null".to_string()
                } else if v.is_undefined() {
                    "undefined".to_string()
                } else {
                    format!("{:?}", v)
                }
            })
            .collect::<Vec<_>>()
            .join(" ");
        tracing::info!("[JS] {}", message);
    })?)?;
    
    // console.error
    console.set("error", Function::new(ctx.clone(), |args: Rest<Value>| {
        let message: String = args.0.iter()
            .map(|v| {
                if let Ok(s) = v.get::<String>() {
                    s
                } else if let Ok(n) = v.get::<f64>() {
                    if n.fract() == 0.0 {
                        format!("{}", n as i64)
                    } else {
                        format!("{}", n)
                    }
                } else if let Ok(b) = v.get::<bool>() {
                    b.to_string()
                } else if v.is_null() {
                    "null".to_string()
                } else if v.is_undefined() {
                    "undefined".to_string()
                } else {
                    format!("{:?}", v)
                }
            })
            .collect::<Vec<_>>()
            .join(" ");
        tracing::error!("[JS] {}", message);
    })?)?;
    
    // console.warn
    console.set("warn", Function::new(ctx.clone(), |args: Rest<Value>| {
        let message: String = args.0.iter()
            .map(|v| {
                if let Ok(s) = v.get::<String>() {
                    s
                } else if let Ok(n) = v.get::<f64>() {
                    if n.fract() == 0.0 {
                        format!("{}", n as i64)
                    } else {
                        format!("{}", n)
                    }
                } else if let Ok(b) = v.get::<bool>() {
                    b.to_string()
                } else if v.is_null() {
                    "null".to_string()
                } else if v.is_undefined() {
                    "undefined".to_string()
                } else {
                    format!("{:?}", v)
                }
            })
            .collect::<Vec<_>>()
            .join(" ");
        tracing::warn!("[JS] {}", message);
    })?)?;
    
    // console.debug
    console.set("debug", Function::new(ctx.clone(), |args: Rest<Value>| {
        let message: String = args.0.iter()
            .map(|v| {
                if let Ok(s) = v.get::<String>() {
                    s
                } else if let Ok(n) = v.get::<f64>() {
                    if n.fract() == 0.0 {
                        format!("{}", n as i64)
                    } else {
                        format!("{}", n)
                    }
                } else if let Ok(b) = v.get::<bool>() {
                    b.to_string()
                } else if v.is_null() {
                    "null".to_string()
                } else if v.is_undefined() {
                    "undefined".to_string()
                } else {
                    format!("{:?}", v)
                }
            })
            .collect::<Vec<_>>()
            .join(" ");
        tracing::debug!("[JS] {}", message);
    })?)?;
    
    globals.set("console", console)?;
    
    Ok(())
}
