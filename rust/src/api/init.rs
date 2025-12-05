use flutter_rust_bridge::frb;

/// 初始化应用
/// 
/// 在 Flutter 启动时调用，传入应用根目录路径
#[frb]
pub async fn init_application(root_path: String) -> anyhow::Result<()> {
    crate::init_application(root_path).await
}

/// FRB 初始化
#[frb(init)]
pub fn init_frb() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// 获取应用是否已初始化
#[frb(sync)]
pub fn is_initialized() -> bool {
    crate::get_root_path().is_some()
}

/// 获取应用根目录
#[frb(sync)]
pub fn get_root_path() -> Option<String> {
    crate::get_root_path().map(|p| p.to_string_lossy().to_string())
}

/// 获取模块目录
#[frb(sync)]
pub fn get_modules_dir() -> Option<String> {
    crate::get_modules_dir().map(|p| p.to_string_lossy().to_string())
}

/// 获取缓存目录
#[frb(sync)]
pub fn get_cache_dir() -> Option<String> {
    crate::get_cache_dir().map(|p| p.to_string_lossy().to_string())
}
