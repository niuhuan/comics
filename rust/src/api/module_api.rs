use flutter_rust_bridge::frb;
use crate::modules::{
    ModuleInfo, Category, ComicSimple, ComicDetail, 
    ComicsPage, EpPage, PicturePage, SortOption,
};

// 由于 ModuleManager 需要状态管理，我们使用全局单例
use once_cell::sync::OnceCell;
use std::sync::Arc;
use tokio::sync::RwLock;
use crate::modules::ModuleManager;

static MODULE_MANAGER: OnceCell<Arc<RwLock<ModuleManager>>> = OnceCell::new();

fn get_module_manager() -> anyhow::Result<&'static Arc<RwLock<ModuleManager>>> {
    MODULE_MANAGER.get()
        .ok_or_else(|| anyhow::anyhow!("Module manager not initialized. Call init_application first."))
}

/// 初始化模块管理器（内部使用）
pub(crate) fn init_module_manager(modules_dir: &std::path::Path) -> anyhow::Result<()> {
    let manager = ModuleManager::new(modules_dir);
    MODULE_MANAGER.set(Arc::new(RwLock::new(manager)))
        .map_err(|_| anyhow::anyhow!("Module manager already initialized"))?;
    Ok(())
}

// ============ Flutter API ============

/// 获取所有已注册的模块列表
#[frb]
pub async fn get_modules() -> anyhow::Result<Vec<ModuleInfo>> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.list_modules().await
}

/// 扫描并注册所有模块
#[frb]
pub async fn scan_and_register_modules() -> anyhow::Result<Vec<ModuleInfo>> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.scan_and_register_all().await
}

/// 注册单个模块
#[frb]
pub async fn register_module(module_id: String) -> anyhow::Result<ModuleInfo> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.register_module(&module_id).await
}

/// 加载模块
#[frb]
pub async fn load_module(module_id: String) -> anyhow::Result<()> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.load_module(&module_id).await
}

/// 卸载模块
#[frb]
pub async fn unload_module(module_id: String) -> anyhow::Result<()> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.unload_module(&module_id).await
}

/// 启用/禁用模块
#[frb]
pub async fn set_module_enabled(module_id: String, enabled: bool) -> anyhow::Result<()> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.set_module_enabled(&module_id, enabled).await
}

/// 获取模块的分类列表
#[frb]
pub async fn get_categories(module_id: String) -> anyhow::Result<Vec<Category>> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_categories(&module_id).await
}

/// 获取排序选项
#[frb]
pub async fn get_sort_options(module_id: String) -> anyhow::Result<Vec<SortOption>> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_sort_options(&module_id).await
}

/// 获取漫画列表 (参考 pikapika comics)
#[frb]
pub async fn get_comics(
    module_id: String, 
    category_slug: String, 
    sort_by: String,
    page: i32
) -> anyhow::Result<ComicsPage> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_comics(&module_id, &category_slug, &sort_by, page).await
}

/// 获取漫画详情 (参考 pikapika album/comicInfo)
#[frb]
pub async fn get_comic_detail(module_id: String, comic_id: String) -> anyhow::Result<ComicDetail> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_comic_detail(&module_id, &comic_id).await
}

/// 获取章节列表 (参考 pikapika eps)
#[frb]
pub async fn get_eps(module_id: String, comic_id: String, page: i32) -> anyhow::Result<EpPage> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_eps(&module_id, &comic_id, page).await
}

/// 获取章节图片 (参考 pikapika pictures)
#[frb]
pub async fn get_pictures(
    module_id: String, 
    comic_id: String, 
    ep_id: String,
    page: i32
) -> anyhow::Result<PicturePage> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_pictures(&module_id, &comic_id, &ep_id, page).await
}

/// 搜索漫画 (参考 pikapika search)
#[frb]
pub async fn search_comics(
    module_id: String, 
    keyword: String, 
    sort_by: String,
    page: i32
) -> anyhow::Result<ComicsPage> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.search(&module_id, &keyword, &sort_by, page).await
}

/// 调用模块的任意函数（高级 API）
#[frb]
pub async fn call_module_function(module_id: String, func_name: String, args_json: String) -> anyhow::Result<String> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.call_function(&module_id, &func_name, &args_json).await
}
