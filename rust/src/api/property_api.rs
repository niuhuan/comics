use flutter_rust_bridge::frb;
use sea_orm::{EntityTrait, QueryFilter, ColumnTrait, ActiveModelTrait, Set};
use chrono::Utc;

use crate::database::{self, entities::property};

/// 保存属性
#[frb]
pub async fn save_property(module_id: String, key: String, value: String) -> anyhow::Result<()> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    let now = Utc::now().naive_utc();
    let id = property::Model::create_id(&module_id, &key);
    
    // 检查是否已存在
    let existing = property::Entity::find_by_id(&id)
        .one(&*conn)
        .await?;
    
    if existing.is_some() {
        // 更新
        let active_model = property::ActiveModel {
            id: Set(id),
            module_id: Set(module_id),
            key: Set(key),
            value: Set(value),
            created_at: sea_orm::ActiveValue::NotSet,
            updated_at: Set(now),
        };
        active_model.update(&*conn).await?;
    } else {
        // 插入
        let active_model = property::ActiveModel {
            id: Set(id),
            module_id: Set(module_id),
            key: Set(key),
            value: Set(value),
            created_at: Set(now),
            updated_at: Set(now),
        };
        active_model.insert(&*conn).await?;
    }
    
    Ok(())
}

/// 加载属性
#[frb]
pub async fn load_property(module_id: String, key: String) -> anyhow::Result<Option<String>> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    let id = property::Model::create_id(&module_id, &key);
    
    let result = property::Entity::find_by_id(&id)
        .one(&*conn)
        .await?;
    
    Ok(result.map(|p| p.value))
}

/// 删除属性
#[frb]
pub async fn delete_property(module_id: String, key: String) -> anyhow::Result<()> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    let id = property::Model::create_id(&module_id, &key);
    
    property::Entity::delete_by_id(&id)
        .exec(&*conn)
        .await?;
    
    Ok(())
}

/// 列出模块的所有属性
#[frb]
pub async fn list_properties(module_id: String) -> anyhow::Result<Vec<PropertyItem>> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    
    let properties = property::Entity::find()
        .filter(property::Column::ModuleId.eq(&module_id))
        .all(&*conn)
        .await?;
    
    Ok(properties.into_iter().map(|p| PropertyItem {
        key: p.key,
        value: p.value,
    }).collect())
}

/// 按前缀列出属性
#[frb]
pub async fn list_properties_by_prefix(module_id: String, prefix: String) -> anyhow::Result<Vec<PropertyItem>> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    
    let properties = property::Entity::find()
        .filter(property::Column::ModuleId.eq(&module_id))
        .filter(property::Column::Key.starts_with(&prefix))
        .all(&*conn)
        .await?;
    
    Ok(properties.into_iter().map(|p| PropertyItem {
        key: p.key,
        value: p.value,
    }).collect())
}

/// 清除模块的所有属性
#[frb]
pub async fn clear_module_properties(module_id: String) -> anyhow::Result<u64> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    
    let result = property::Entity::delete_many()
        .filter(property::Column::ModuleId.eq(&module_id))
        .exec(&*conn)
        .await?;
    
    Ok(result.rows_affected)
}

/// 属性项
#[derive(Debug, Clone)]
pub struct PropertyItem {
    pub key: String,
    pub value: String,
}
