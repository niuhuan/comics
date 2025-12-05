use flutter_rust_bridge::frb;
use crate::modules::{ModuleInfo, Category, ComicSimple, ComicDetail, ChapterImages, ComicListResponse, SearchParams};

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

/// 获取漫画列表
#[frb]
pub async fn get_comic_list(module_id: String, category_id: String, page: i32) -> anyhow::Result<ComicListResponse> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_comic_list(&module_id, &category_id, page).await
}

/// 获取漫画详情
#[frb]
pub async fn get_comic_detail(module_id: String, comic_id: String) -> anyhow::Result<ComicDetail> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_comic_detail(&module_id, &comic_id).await
}

/// 获取章节图片
#[frb]
pub async fn get_chapter_images(module_id: String, comic_id: String, chapter_id: String) -> anyhow::Result<ChapterImages> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.get_chapter_images(&module_id, &comic_id, &chapter_id).await
}

/// 搜索漫画
#[frb]
pub async fn search_comics(module_id: String, keyword: String, page: i32) -> anyhow::Result<ComicListResponse> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    let params = SearchParams {
        keyword,
        page,
        page_size: 20,
    };
    m.search(&module_id, params).await
}

/// 调用模块的任意函数（高级 API）
#[frb]
pub async fn call_module_function(module_id: String, func_name: String, args_json: String) -> anyhow::Result<String> {
    let manager = get_module_manager()?;
    let m = manager.read().await;
    m.call_function(&module_id, &func_name, &args_json).await
}
