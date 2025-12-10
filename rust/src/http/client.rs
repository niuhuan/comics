use reqwest::{Client, Method, Response};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;

use crate::http::proxy::ProxyManager;

/// HTTP 请求配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpRequest {
    pub url: String,
    pub method: String,
    #[serde(default)]
    pub headers: HashMap<String, String>,
    #[serde(default)]
    pub body: Option<String>,
    #[serde(default = "default_timeout")]
    pub timeout_secs: u64,
}

fn default_timeout() -> u64 {
    30
}

/// HTTP 响应
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: HashMap<String, String>,
    pub body: String,
    pub content_type: String,
}

/// HTTP 客户端
pub struct HttpClient {
    client: Client,
}

impl HttpClient {
    pub fn new() -> anyhow::Result<Self> {
        Self::with_config(30, None)
    }

    pub fn with_config(timeout_secs: u64, user_agent: Option<String>) -> anyhow::Result<Self> {
        let mut builder = Client::builder()
            .timeout(Duration::from_secs(timeout_secs))
            .connect_timeout(Duration::from_secs(10))
            .pool_max_idle_per_host(10)
            .danger_accept_invalid_certs(true);  // 禁用证书验证（用于分流IP访问）
        
        if let Some(ua) = user_agent {
            builder = builder.user_agent(ua);
        }
        
        // 从代理管理器获取代理配置
        if let Some(proxy_result) = ProxyManager::instance().get_reqwest_proxy() {
            match proxy_result {
                Ok(proxy) => {
                    builder = builder.proxy(proxy);
                    tracing::debug!("HTTP 客户端已配置代理");
                }
                Err(e) => {
                    tracing::warn!("配置代理失败，将不使用代理: {}", e);
                }
            }
        }
        
        let client = builder.build()?;
        
        Ok(Self { client })
    }

    /// 发送 HTTP 请求
    pub async fn request(&self, req: HttpRequest) -> anyhow::Result<HttpResponse> {
        let method = match req.method.to_uppercase().as_str() {
            "GET" => Method::GET,
            "POST" => Method::POST,
            "PUT" => Method::PUT,
            "DELETE" => Method::DELETE,
            "PATCH" => Method::PATCH,
            "HEAD" => Method::HEAD,
            "OPTIONS" => Method::OPTIONS,
            _ => return Err(anyhow::anyhow!("Unsupported HTTP method: {}", req.method)),
        };

        let mut request_builder = self.client
            .request(method, &req.url)
            .timeout(Duration::from_secs(req.timeout_secs));

        // 添加 headers
        for (key, value) in &req.headers {
            request_builder = request_builder.header(key.as_str(), value.as_str());
        }

        // 添加 body
        if let Some(body) = req.body {
            request_builder = request_builder.body(body);
        }

        let response = request_builder.send().await?;
        
        Self::parse_response(response).await
    }

    /// GET 请求
    pub async fn get(&self, url: &str, headers: HashMap<String, String>) -> anyhow::Result<HttpResponse> {
        self.request(HttpRequest {
            url: url.to_string(),
            method: "GET".to_string(),
            headers,
            body: None,
            timeout_secs: 30,
        }).await
    }

    /// POST 请求
    pub async fn post(&self, url: &str, headers: HashMap<String, String>, body: Option<String>) -> anyhow::Result<HttpResponse> {
        self.request(HttpRequest {
            url: url.to_string(),
            method: "POST".to_string(),
            headers,
            body,
            timeout_secs: 30,
        }).await
    }

    /// 下载文件（返回字节）
    pub async fn download(&self, url: &str, headers: HashMap<String, String>) -> anyhow::Result<Vec<u8>> {
        let mut request_builder = self.client
            .get(url)
            .timeout(Duration::from_secs(300));

        for (key, value) in &headers {
            request_builder = request_builder.header(key.as_str(), value.as_str());
        }

        let response = request_builder.send().await?;
        
        if !response.status().is_success() {
            return Err(anyhow::anyhow!("Download failed with status: {}", response.status()));
        }

        let bytes = response.bytes().await?;
        Ok(bytes.to_vec())
    }

    async fn parse_response(response: Response) -> anyhow::Result<HttpResponse> {
        let status = response.status().as_u16();
        
        let mut headers = HashMap::new();
        for (key, value) in response.headers().iter() {
            if let Ok(v) = value.to_str() {
                headers.insert(key.to_string(), v.to_string());
            }
        }

        let content_type = headers
            .get("content-type")
            .cloned()
            .unwrap_or_else(|| "text/plain".to_string());

        let body = response.text().await?;

        Ok(HttpResponse {
            status,
            headers,
            body,
            content_type,
        })
    }
}

impl Default for HttpClient {
    fn default() -> Self {
        Self::new().expect("Failed to create HTTP client")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_http_client() {
        let client = HttpClient::new().unwrap();
        let response = client.get("https://httpbin.org/get", HashMap::new()).await;
        assert!(response.is_ok());
    }
}
