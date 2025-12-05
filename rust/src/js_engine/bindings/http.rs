use rquickjs::{Ctx, Function, Object, Value};
use anyhow::Result;
use std::collections::HashMap;

use crate::http::{HttpClient, HttpRequest};

/// 注册 http 对象到 JS 全局
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    let http = Object::new(ctx.clone())?;
    
    // http.get(url, headers?) -> Promise<Response>
    // 由于 rquickjs 异步处理较复杂，这里使用同步版本
    // 实际使用中会通过 Rust 端异步调用，然后返回结果给 JS
    
    // 注册一个标记，表示 http 模块可用
    http.set("_available", true)?;
    
    // http.request(config) - 返回请求配置的 JSON，由 Rust 端执行
    http.set("_request", Function::new(ctx.clone(), |config: String| -> String {
        // 这个函数只是记录请求，实际执行由 Rust 端处理
        config
    })?)?;
    
    globals.set("__http__", http)?;
    
    // 注册辅助函数用于构建请求
    let http_helper = r#"
        const http = {
            async get(url, headers = {}) {
                return await __native_http_request__({
                    url: url,
                    method: 'GET',
                    headers: headers
                });
            },
            async post(url, headers = {}, body = null) {
                return await __native_http_request__({
                    url: url,
                    method: 'POST',
                    headers: headers,
                    body: body
                });
            },
            async request(config) {
                return await __native_http_request__(config);
            }
        };
    "#;
    
    let _: Value = ctx.eval(http_helper)?;
    
    Ok(())
}

/// 执行 HTTP 请求（供 Rust 端调用）
pub async fn execute_http_request(config_json: &str) -> Result<String> {
    let request: HttpRequest = serde_json::from_str(config_json)?;
    let client = HttpClient::new()?;
    let response = client.request(request).await?;
    let response_json = serde_json::to_string(&response)?;
    Ok(response_json)
}
