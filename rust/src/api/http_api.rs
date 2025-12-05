use flutter_rust_bridge::frb;
use std::collections::HashMap;

use crate::http::{HttpClient, HttpRequest, HttpResponse};

/// 发送 HTTP GET 请求
#[frb]
pub async fn http_get(url: String, headers: HashMap<String, String>) -> anyhow::Result<HttpResponseDto> {
    let client = HttpClient::new()?;
    let response = client.get(&url, headers).await?;
    Ok(response.into())
}

/// 发送 HTTP POST 请求
#[frb]
pub async fn http_post(url: String, headers: HashMap<String, String>, body: Option<String>) -> anyhow::Result<HttpResponseDto> {
    let client = HttpClient::new()?;
    let response = client.post(&url, headers, body).await?;
    Ok(response.into())
}

/// 发送自定义 HTTP 请求
#[frb]
pub async fn http_request(
    url: String,
    method: String,
    headers: HashMap<String, String>,
    body: Option<String>,
    timeout_secs: u64,
) -> anyhow::Result<HttpResponseDto> {
    let client = HttpClient::new()?;
    let request = HttpRequest {
        url,
        method,
        headers,
        body,
        timeout_secs,
    };
    let response = client.request(request).await?;
    Ok(response.into())
}

/// 下载文件
#[frb]
pub async fn http_download(url: String, headers: HashMap<String, String>) -> anyhow::Result<Vec<u8>> {
    let client = HttpClient::new()?;
    client.download(&url, headers).await
}

/// HTTP 响应 DTO（用于 Flutter）
#[derive(Debug, Clone)]
pub struct HttpResponseDto {
    pub status: u16,
    pub headers: HashMap<String, String>,
    pub body: String,
    pub content_type: String,
}

impl From<HttpResponse> for HttpResponseDto {
    fn from(resp: HttpResponse) -> Self {
        Self {
            status: resp.status,
            headers: resp.headers,
            body: resp.body,
            content_type: resp.content_type,
        }
    }
}
