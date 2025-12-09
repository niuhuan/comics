use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::RwLock;
use anyhow::Result;
use sea_orm::{EntityTrait, ActiveModelTrait, Set};
use chrono::Utc;

use crate::database::{self, entities::module_info};
use crate::js_engine::{JsRuntime, ModuleLoader};
use super::types::*;

/// 模块运行时实例
struct ModuleInstance {
    #[allow(dead_code)]
    info: ModuleInfo,
    runtime: JsRuntime,
}

/// 模块管理器
pub struct ModuleManager {
    #[allow(dead_code)]
    modules_dir: std::path::PathBuf,
    loader: ModuleLoader,
    instances: RwLock<HashMap<String, Arc<ModuleInstance>>>,
}

impl ModuleManager {
    pub fn new(modules_dir: &Path) -> Self {
        Self {
            modules_dir: modules_dir.to_path_buf(),
            loader: ModuleLoader::new(modules_dir),
            instances: RwLock::new(HashMap::new()),
        }
    }

    /// 获取所有已注册的模块
    pub async fn list_modules(&self) -> Result<Vec<ModuleInfo>> {
        let db = database::get_database()
            .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
        
        let conn = db.read().await;
        let modules = module_info::Entity::find()
            .all(&*conn)
            .await?;
        
        Ok(modules.into_iter().map(|m| ModuleInfo {
            id: m.id,
            name: m.name,
            version: m.version,
            author: String::new(),
            description: m.description,
            icon: None,
            enabled: m.enabled,
        }).collect())
    }

    /// 注册/更新模块
    pub async fn register_module(&self, module_id: &str) -> Result<ModuleInfo> {
        // 加载脚本
        let script = self.loader.load_script(module_id).await?;
        
        // 验证脚本
        self.loader.validate_script(&script)?;
        
        // 提取元信息
        let metadata = self.loader.extract_metadata(&script)?;
        
        // 保存到数据库
        let db = database::get_database()
            .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
        
        let conn = db.read().await;
        let now = Utc::now().naive_utc();
        
        // 检查是否已存在
        let existing = module_info::Entity::find_by_id(&metadata.id)
            .one(&*conn)
            .await?;
        
        if let Some(_) = existing {
            // 更新
            let active_model = module_info::ActiveModel {
                id: Set(metadata.id.clone()),
                name: Set(metadata.name.clone()),
                version: Set(metadata.version.clone()),
                description: Set(metadata.description.clone()),
                script_path: Set(format!("{}.js", module_id)),
                enabled: Set(true),
                created_at: sea_orm::ActiveValue::NotSet,
                updated_at: Set(now),
            };
            active_model.update(&*conn).await?;
        } else {
            // 插入
            let active_model = module_info::ActiveModel {
                id: Set(metadata.id.clone()),
                name: Set(metadata.name.clone()),
                version: Set(metadata.version.clone()),
                description: Set(metadata.description.clone()),
                script_path: Set(format!("{}.js", module_id)),
                enabled: Set(true),
                created_at: Set(now),
                updated_at: Set(now),
            };
            active_model.insert(&*conn).await?;
        }
        
        tracing::debug!("Module registered: {} v{}", metadata.name, metadata.version);
        
        Ok(ModuleInfo {
            id: metadata.id,
            name: metadata.name,
            version: metadata.version,
            author: String::new(),
            description: metadata.description,
            icon: None,
            enabled: true,
        })
    }

    /// 加载模块（创建运行时实例）
    pub async fn load_module(&self, module_id: &str) -> Result<()> {
        // 检查是否已加载
        {
            let instances = self.instances.read().await;
            if instances.contains_key(module_id) {
                return Ok(());
            }
        }
        
        // 获取模块信息
        let db = database::get_database()
            .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
        
        let conn = db.read().await;
        let module = module_info::Entity::find_by_id(module_id)
            .one(&*conn)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Module not found: {}", module_id))?;
        
        if !module.enabled {
            return Err(anyhow::anyhow!("Module is disabled: {}", module_id));
        }
        
        // 加载脚本
        let script = self.loader.load_script(module_id).await?;
        
        // 创建 JS 运行时
        let runtime = JsRuntime::new()?;
        runtime.load_module(module_id, &script)?;
        
        // 保存实例
        let instance = Arc::new(ModuleInstance {
            info: ModuleInfo {
                id: module.id,
                name: module.name,
                version: module.version,
                author: String::new(),
                description: module.description,
                icon: None,
                enabled: module.enabled,
            },
            runtime,
        });
        
        {
            let mut instances = self.instances.write().await;
            instances.insert(module_id.to_string(), instance);
        }
        
        tracing::debug!("Module loaded: {}", module_id);
        
        Ok(())
    }

    /// 卸载模块
    pub async fn unload_module(&self, module_id: &str) -> Result<()> {
        let mut instances = self.instances.write().await;
        instances.remove(module_id);
        tracing::debug!("Module unloaded: {}", module_id);
        Ok(())
    }

    /// 启用/禁用模块
    pub async fn set_module_enabled(&self, module_id: &str, enabled: bool) -> Result<()> {
        let db = database::get_database()
            .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
        
        let conn = db.read().await;
        let now = Utc::now().naive_utc();
        
        let module = module_info::Entity::find_by_id(module_id)
            .one(&*conn)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Module not found: {}", module_id))?;
        
        let mut active_model: module_info::ActiveModel = module.into();
        active_model.enabled = Set(enabled);
        active_model.updated_at = Set(now);
        active_model.update(&*conn).await?;
        
        if !enabled {
            self.unload_module(module_id).await?;
        }
        
        Ok(())
    }

    /// 调用模块函数
    pub async fn call_function(&self, module_id: &str, func_name: &str, args_json: &str) -> Result<String> {
        tracing::debug!("call_function: module={}, func={}, args={}", module_id, func_name, args_json);
        
        // 确保模块已加载
        self.load_module(module_id).await?;
        
        let instances = self.instances.read().await;
        let instance = instances.get(module_id)
            .ok_or_else(|| anyhow::anyhow!("Module not loaded: {}", module_id))?;
        
        tracing::debug!("Calling JS function: {}", func_name);
        let result = instance.runtime.call_function_json(func_name, args_json)?;
        tracing::debug!("JS function returned: {} bytes", result.len());
        
        Ok(result)
    }

    /// 获取分类列表
    pub async fn get_categories(&self, module_id: &str) -> Result<Vec<Category>> {
        tracing::debug!("Getting categories for module: {}", module_id);
        let result = self.call_function(module_id, "getCategories", "{}").await?;
        tracing::debug!("getCategories result: {}", &result[..std::cmp::min(500, result.len())]);
        let categories: Vec<Category> = serde_json::from_str(&result)?;
        tracing::debug!("Parsed {} categories", categories.len());
        Ok(categories)
    }

    /// 获取排序选项
    pub async fn get_sort_options(&self, module_id: &str) -> Result<Vec<SortOption>> {
        let result = self.call_function(module_id, "getSortOptions", "{}").await?;
        let options: Vec<SortOption> = serde_json::from_str(&result)?;
        Ok(options)
    }

    /// 获取漫画列表 (参考 pikapika comics)
    pub async fn get_comics(&self, module_id: &str, category_slug: &str, sort_by: &str, page: i32) -> Result<ComicsPage> {
        let args = serde_json::json!({
            "categorySlug": category_slug,
            "sortBy": sort_by,
            "page": page
        });
        let result = self.call_function(module_id, "getComics", &args.to_string()).await?;
        tracing::debug!("getComics raw result (first 1000 chars): {}", &result[..std::cmp::min(1000, result.len())]);
        
        // 尝试解析，如果失败则输出更详细的错误信息
        let response: ComicsPage = match serde_json::from_str::<ComicsPage>(&result) {
            Ok(r) => {
                tracing::debug!("Successfully parsed ComicsPage with {} docs", r.docs.len());
                r
            },
            Err(e) => {
                tracing::error!("Failed to parse ComicsPage: {}", e);
                tracing::error!("Full JSON string (first 2000 chars): {}", &result[..std::cmp::min(2000, result.len())]);
                
                // 尝试手动检查 JSON 结构
                if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(&result) {
                    tracing::error!("Parsed as Value, structure: {:?}", json_value);
                    if let Some(docs) = json_value.get("docs") {
                        if let Some(first_doc) = docs.as_array().and_then(|a| a.first()) {
                            tracing::error!("First doc structure: {:?}", first_doc);
                            if let Some(id_field) = first_doc.get("id") {
                                tracing::error!("First doc id type: {:?}, value: {:?}", id_field, id_field);
                            }
                        }
                    }
                }
                
                return Err(anyhow::anyhow!("Failed to parse ComicsPage: {}", e));
            }
        };
        Ok(response)
    }

    /// 获取漫画详情
    pub async fn get_comic_detail(&self, module_id: &str, comic_id: &str) -> Result<ComicDetail> {
        let args = serde_json::json!({
            "comicId": comic_id
        });
        let result = self.call_function(module_id, "getComicDetail", &args.to_string()).await?;
        let detail: ComicDetail = serde_json::from_str(&result)?;
        Ok(detail)
    }

    /// 获取章节列表 (参考 pikapika eps)
    pub async fn get_eps(&self, module_id: &str, comic_id: &str, page: i32) -> Result<EpPage> {
        let args = serde_json::json!({
            "comicId": comic_id,
            "page": page
        });
        let result = self.call_function(module_id, "getEps", &args.to_string()).await?;
        let eps: EpPage = serde_json::from_str(&result)?;
        Ok(eps)
    }

    /// 获取章节图片 (参考 pikapika pictures)
    pub async fn get_pictures(&self, module_id: &str, comic_id: &str, ep_id: &str, page: i32) -> Result<PicturePage> {
        let args = serde_json::json!({
            "comicId": comic_id,
            "epId": ep_id,
            "page": page
        });
        let result = self.call_function(module_id, "getPictures", &args.to_string()).await?;
        let pictures: PicturePage = serde_json::from_str(&result)?;
        Ok(pictures)
    }

    /// 搜索漫画 (参考 pikapika search)
    pub async fn search(&self, module_id: &str, keyword: &str, sort_by: &str, page: i32) -> Result<ComicsPage> {
        let args = serde_json::json!({
            "keyword": keyword,
            "sortBy": sort_by,
            "page": page
        });
        let result = self.call_function(module_id, "search", &args.to_string()).await?;
        let response: ComicsPage = serde_json::from_str(&result)?;
        Ok(response)
    }

    /// 扫描并注册所有模块
    pub async fn scan_and_register_all(&self) -> Result<Vec<ModuleInfo>> {
        let module_ids = self.loader.list_modules().await?;
        let mut registered = Vec::new();
        
        for module_id in module_ids {
            match self.register_module(&module_id).await {
                Ok(info) => registered.push(info),
                Err(e) => tracing::error!("Failed to register module {}: {}", module_id, e),
            }
        }
        
        Ok(registered)
    }
}
