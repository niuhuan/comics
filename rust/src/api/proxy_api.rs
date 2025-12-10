use flutter_rust_bridge::frb;
use crate::http::proxy::ProxyManager;
use crate::api::property_api;

const PROXY_SETTING_KEY: &str = "proxy_url";

/// 设置代理
/// 
/// # 参数
/// - `url`: 代理 URL，支持 http:// 和 socks5:// 协议。如果为空字符串或 None，则清除代理。
#[frb]
pub async fn set_proxy(url: Option<String>) -> anyhow::Result<()> {
    let proxy_url = url.as_ref()
        .map(|s| s.trim())
        .and_then(|s| if s.is_empty() { None } else { Some(s.to_string()) });
    
    // 更新代理管理器
    ProxyManager::instance().set_proxy(proxy_url.clone())?;
    
    // 保存到数据库
    if let Some(url) = &proxy_url {
        property_api::save_app_setting(PROXY_SETTING_KEY.to_string(), url.clone()).await?;
    } else {
        property_api::delete_app_setting(PROXY_SETTING_KEY.to_string()).await?;
    }
    
    tracing::info!("代理设置已保存: {:?}", proxy_url);
    Ok(())
}

/// 获取当前代理设置
#[frb]
pub async fn get_proxy() -> anyhow::Result<Option<String>> {
    // 先从代理管理器获取（内存中的值）
    if let Some(config) = ProxyManager::instance().get_proxy() {
        return Ok(Some(config.url));
    }
    
    // 如果内存中没有，从数据库加载
    let url = property_api::load_app_setting(PROXY_SETTING_KEY.to_string()).await?;
    
    // 如果数据库中有，同步到代理管理器
    if let Some(ref url) = url {
        ProxyManager::instance().set_proxy(Some(url.clone()))?;
    }
    
    Ok(url)
}

/// 清除代理设置
#[frb]
pub async fn clear_proxy() -> anyhow::Result<()> {
    ProxyManager::instance().clear_proxy()?;
    property_api::delete_app_setting(PROXY_SETTING_KEY.to_string()).await?;
    tracing::info!("代理设置已清除");
    Ok(())
}

/// 初始化代理设置（从数据库加载）
/// 在应用启动时调用（内部使用，不导出到 Flutter）
pub(crate) async fn init_proxy() -> anyhow::Result<()> {
    let url = property_api::load_app_setting(PROXY_SETTING_KEY.to_string()).await?;
    
    if let Some(url) = url {
        ProxyManager::instance().set_proxy(Some(url))?;
        tracing::info!("代理设置已从数据库加载");
    } else {
        ProxyManager::instance().clear_proxy()?;
        tracing::info!("未找到代理设置，使用默认配置（无代理）");
    }
    
    Ok(())
}

