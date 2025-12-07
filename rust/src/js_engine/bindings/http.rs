use rquickjs::{Ctx, Function, Value};
use anyhow::Result;

use crate::http::{HttpClient, HttpRequest};

/// 注册 http 对象到 JS 全局
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    // 注册同步的 HTTP 请求函数
    // 这个函数会阻塞等待 HTTP 请求完成
    globals.set("__native_http_request_sync__", Function::new(ctx.clone(), |config_json: String| -> String {
        tracing::debug!("[JS HTTP] Received request: {}", &config_json[..config_json.len().min(200)]);
        
        // 解析请求配置
        let request: HttpRequest = match serde_json::from_str(&config_json) {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("[JS HTTP] Failed to parse request: {}", e);
                return serde_json::to_string(&serde_json::json!({
                    "error": format!("Failed to parse request: {}", e)
                })).unwrap_or_default();
            }
        };
        
        tracing::debug!("[JS HTTP] Making {} request to: {}", request.method, request.url);
        
        // 使用 tokio 的阻塞线程执行异步请求
        // 注意：这会阻塞当前线程，但 QuickJS 是单线程的所以没问题
        let result = std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let client = HttpClient::new()?;
                client.request(request).await
            })
        }).join();
        
        match result {
            Ok(Ok(response)) => {
                tracing::debug!("[JS HTTP] Response status: {}", response.status);
                serde_json::to_string(&response).unwrap_or_else(|e| {
                    serde_json::to_string(&serde_json::json!({
                        "error": format!("Failed to serialize response: {}", e)
                    })).unwrap_or_default()
                })
            }
            Ok(Err(e)) => {
                tracing::error!("[JS HTTP] Request failed: {:?}", e);
                serde_json::to_string(&serde_json::json!({
                    "error": format!("Request failed: {:?}", e)
                })).unwrap_or_default()
            }
            Err(_) => {
                tracing::error!("[JS HTTP] Thread panicked");
                serde_json::to_string(&serde_json::json!({
                    "error": "HTTP request thread panicked"
                })).unwrap_or_default()
            }
        }
    })?)?;
    
    // 注册辅助 JS 代码
    // 提供 http.get/post/request 接口
    let http_helper = r#"
        const http = {
            get: function(url, headers) {
                headers = headers || {};
                var config = JSON.stringify({
                    url: url,
                    method: 'GET',
                    headers: headers,
                    timeout_secs: 30
                });
                var responseJson = __native_http_request_sync__(config);
                return JSON.parse(responseJson);
            },
            post: function(url, headers, body) {
                headers = headers || {};
                var config = JSON.stringify({
                    url: url,
                    method: 'POST',
                    headers: headers,
                    body: body || null,
                    timeout_secs: 30
                });
                var responseJson = __native_http_request_sync__(config);
                return JSON.parse(responseJson);
            },
            request: function(config) {
                config.timeout_secs = config.timeout_secs || 30;
                var configJson = JSON.stringify(config);
                var responseJson = __native_http_request_sync__(configJson);
                return JSON.parse(responseJson);
            }
        };
    "#;
    
    let _: Value = ctx.eval(http_helper)?;
    
    tracing::debug!("[JS HTTP] HTTP bindings registered");
    
    Ok(())
}

/// 执行 HTTP 请求（供 Rust 端调用）- 保留用于其他用途
pub async fn execute_http_request(config_json: &str) -> Result<String> {
    let request: HttpRequest = serde_json::from_str(config_json)?;
    let client = HttpClient::new()?;
    let response = client.request(request).await?;
    let response_json = serde_json::to_string(&response)?;
    Ok(response_json)
}
