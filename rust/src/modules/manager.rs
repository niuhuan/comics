use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::RwLock;
use anyhow::Result;
use sea_orm::{EntityTrait, QueryFilter, ColumnTrait, ActiveModelTrait, Set};
use chrono::Utc;

use crate::database::{self, entities::module_info};
use crate::js_engine::{JsRuntime, ModuleLoader};
use super::types::*;

/// 模块运行时实例
struct ModuleInstance {
    info: ModuleInfo,
    runtime: JsRuntime,
}

/// 模块管理器
pub struct ModuleManager {
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
            description: m.description,
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
        
        tracing::info!("Module registered: {} v{}", metadata.name, metadata.version);
        
        Ok(ModuleInfo {
            id: metadata.id,
            name: metadata.name,
            version: metadata.version,
            description: metadata.description,
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
                description: module.description,
                enabled: module.enabled,
            },
            runtime,
        });
        
        {
            let mut instances = self.instances.write().await;
            instances.insert(module_id.to_string(), instance);
        }
        
        tracing::info!("Module loaded: {}", module_id);
        
        Ok(())
    }

    /// 卸载模块
    pub async fn unload_module(&self, module_id: &str) -> Result<()> {
        let mut instances = self.instances.write().await;
        instances.remove(module_id);
        tracing::info!("Module unloaded: {}", module_id);
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
        // 确保模块已加载
        self.load_module(module_id).await?;
        
        let instances = self.instances.read().await;
        let instance = instances.get(module_id)
            .ok_or_else(|| anyhow::anyhow!("Module not loaded: {}", module_id))?;
        
        let result = instance.runtime.call_function_json(func_name, args_json)?;
        
        Ok(result)
    }

    /// 获取分类列表
    pub async fn get_categories(&self, module_id: &str) -> Result<Vec<Category>> {
        let result = self.call_function(module_id, "getCategories", "{}").await?;
        let categories: Vec<Category> = serde_json::from_str(&result)?;
        Ok(categories)
    }

    /// 获取漫画列表
    pub async fn get_comic_list(&self, module_id: &str, category_id: &str, page: i32) -> Result<ComicListResponse> {
        let args = serde_json::json!({
            "categoryId": category_id,
            "page": page
        });
        let result = self.call_function(module_id, "getComicList", &args.to_string()).await?;
        let response: ComicListResponse = serde_json::from_str(&result)?;
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

    /// 获取章节图片
    pub async fn get_chapter_images(&self, module_id: &str, comic_id: &str, chapter_id: &str) -> Result<ChapterImages> {
        let args = serde_json::json!({
            "comicId": comic_id,
            "chapterId": chapter_id
        });
        let result = self.call_function(module_id, "getChapterImages", &args.to_string()).await?;
        let images: ChapterImages = serde_json::from_str(&result)?;
        Ok(images)
    }

    /// 搜索漫画
    pub async fn search(&self, module_id: &str, params: SearchParams) -> Result<ComicListResponse> {
        let args = serde_json::to_string(&params)?;
        let result = self.call_function(module_id, "search", &args).await?;
        let response: ComicListResponse = serde_json::from_str(&result)?;
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
