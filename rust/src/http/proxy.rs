use once_cell::sync::Lazy;
use std::sync::RwLock;
use reqwest::Proxy as ReqwestProxy;

/// 代理配置
#[derive(Debug, Clone, PartialEq)]
pub struct ProxyConfig {
    pub url: String,
}

impl ProxyConfig {
    pub fn new(url: String) -> Self {
        Self { url }
    }

    /// 从字符串创建代理配置
    /// 支持 http:// 和 socks5:// 协议
    pub fn from_str(url: &str) -> anyhow::Result<Self> {
        let url = url.trim();
        if url.is_empty() {
            return Err(anyhow::anyhow!("代理 URL 不能为空"));
        }

        // 验证协议
        if !url.starts_with("http://") && !url.starts_with("socks5://") {
            return Err(anyhow::anyhow!("代理 URL 必须以 http:// 或 socks5:// 开头"));
        }

        Ok(Self {
            url: url.to_string(),
        })
    }

    /// 转换为 reqwest::Proxy
    pub fn to_reqwest_proxy(&self) -> anyhow::Result<ReqwestProxy> {
        ReqwestProxy::all(&self.url)
            .map_err(|e| anyhow::anyhow!("创建代理失败: {}", e))
    }
}

/// 代理管理器（单例模式）
pub struct ProxyManager {
    config: RwLock<Option<ProxyConfig>>,
}

impl ProxyManager {
    fn new() -> Self {
        Self {
            config: RwLock::new(None),
        }
    }

    /// 获取全局代理管理器实例
    pub fn instance() -> &'static ProxyManager {
        static INSTANCE: Lazy<ProxyManager> = Lazy::new(|| ProxyManager::new());
        &INSTANCE
    }

    /// 设置代理
    pub fn set_proxy(&self, url: Option<String>) -> anyhow::Result<()> {
        let mut config = self.config.write()
            .map_err(|e| anyhow::anyhow!("获取代理配置锁失败: {}", e))?;
        
        *config = match url {
            Some(url) if !url.trim().is_empty() => {
                Some(ProxyConfig::from_str(&url)?)
            }
            _ => None,
        };
        
        tracing::info!("代理设置已更新: {:?}", config);
        Ok(())
    }

    /// 获取当前代理配置
    pub fn get_proxy(&self) -> Option<ProxyConfig> {
        let config = self.config.read().ok()?;
        config.clone()
    }

    /// 清除代理
    pub fn clear_proxy(&self) -> anyhow::Result<()> {
        self.set_proxy(None)
    }

    /// 获取 reqwest::Proxy（用于构建 HTTP 客户端）
    pub fn get_reqwest_proxy(&self) -> Option<anyhow::Result<ReqwestProxy>> {
        let config = self.get_proxy()?;
        Some(config.to_reqwest_proxy())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proxy_config_from_str() {
        // 测试 HTTP 代理
        let config = ProxyConfig::from_str("http://127.0.0.1:8080").unwrap();
        assert_eq!(config.url, "http://127.0.0.1:8080");

        // 测试 SOCKS5 代理
        let config = ProxyConfig::from_str("socks5://127.0.0.1:1080").unwrap();
        assert_eq!(config.url, "socks5://127.0.0.1:1080");

        // 测试无效协议
        assert!(ProxyConfig::from_str("ftp://127.0.0.1:8080").is_err());

        // 测试空字符串
        assert!(ProxyConfig::from_str("").is_err());
    }

    #[test]
    fn test_proxy_manager() {
        let manager = ProxyManager::instance();

        // 设置代理
        manager.set_proxy(Some("http://127.0.0.1:8080".to_string())).unwrap();
        assert!(manager.get_proxy().is_some());
        assert_eq!(manager.get_proxy().unwrap().url, "http://127.0.0.1:8080");

        // 清除代理
        manager.clear_proxy().unwrap();
        assert!(manager.get_proxy().is_none());
    }
}

