use rquickjs::{Ctx, Function, Value};
use anyhow::Result;
use crate::database;
use crate::database::entities::property;
use sea_orm::{EntityTrait, Set, ActiveModelTrait};
use chrono::Utc;

/// 注册 storage 对象到 JS 全局
/// 
/// storage 提供模块级别的键值存储，数据按 module_id 隔离
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    // 同步版本的 storage get
    globals.set("__native_storage_get_sync__", Function::new(ctx.clone(), |module_id: String, key: String| -> String {
        tracing::debug!("[JS Storage] get: module={}, key={}", module_id, key);
        
        let result = std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let db = match database::get_database() {
                    Some(d) => d,
                    None => return None::<String>,
                };
                let conn = db.read().await;
                let id = property::Model::create_id(&module_id, &key);
                
                property::Entity::find_by_id(&id)
                    .one(&*conn)
                    .await
                    .ok()
                    .flatten()
                    .map(|m| m.value)
            })
        }).join();
        
        match result {
            Ok(Some(value)) => value,
            _ => String::new()
        }
    })?)?;
    
    // 同步版本的 storage set
    globals.set("__native_storage_set_sync__", Function::new(ctx.clone(), |module_id: String, key: String, value: String| -> bool {
        tracing::debug!("[JS Storage] set: module={}, key={}, value_len={}", module_id, key, value.len());
        
        let result = std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let db = match database::get_database() {
                    Some(d) => d,
                    None => return false,
                };
                let conn = db.read().await;
                let id = property::Model::create_id(&module_id, &key);
                let now = Utc::now().naive_utc();
                
                // 先尝试找到现有记录
                let existing = property::Entity::find_by_id(&id)
                    .one(&*conn)
                    .await
                    .ok()
                    .flatten();
                
                if existing.is_some() {
                    // 更新
                    let active = property::ActiveModel {
                        id: Set(id),
                        module_id: Set(module_id),
                        key: Set(key),
                        value: Set(value),
                        created_at: sea_orm::ActiveValue::NotSet,
                        updated_at: Set(now),
                    };
                    active.update(&*conn).await.is_ok()
                } else {
                    // 插入
                    let active = property::ActiveModel {
                        id: Set(id),
                        module_id: Set(module_id),
                        key: Set(key),
                        value: Set(value),
                        created_at: Set(now),
                        updated_at: Set(now),
                    };
                    active.insert(&*conn).await.is_ok()
                }
            })
        }).join();
        
        result.unwrap_or(false)
    })?)?;
    
    // 同步版本的 storage remove
    globals.set("__native_storage_remove_sync__", Function::new(ctx.clone(), |module_id: String, key: String| -> bool {
        tracing::debug!("[JS Storage] remove: module={}, key={}", module_id, key);
        
        let result = std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let db = match database::get_database() {
                    Some(d) => d,
                    None => return false,
                };
                let conn = db.read().await;
                let id = property::Model::create_id(&module_id, &key);
                
                property::Entity::delete_by_id(&id)
                    .exec(&*conn)
                    .await
                    .is_ok()
            })
        }).join();
        
        result.unwrap_or(false)
    })?)?;
    
    // 注册辅助函数 - 同步版本
    // 注意：__MODULE_ID__ 在加载模块时设置
    let storage_helper = r#"
        const storage = {
            get: function(key) {
                var moduleId = typeof __MODULE_ID__ !== 'undefined' ? __MODULE_ID__ : 'default';
                var result = __native_storage_get_sync__(moduleId, key);
                return result || null;
            },
            set: function(key, value) {
                var moduleId = typeof __MODULE_ID__ !== 'undefined' ? __MODULE_ID__ : 'default';
                return __native_storage_set_sync__(moduleId, key, String(value));
            },
            remove: function(key) {
                var moduleId = typeof __MODULE_ID__ !== 'undefined' ? __MODULE_ID__ : 'default';
                return __native_storage_remove_sync__(moduleId, key);
            }
        };
    "#;
    
    let _: Value = ctx.eval(storage_helper)?;
    
    tracing::debug!("[JS Storage] Storage bindings registered");
    
    Ok(())
}
