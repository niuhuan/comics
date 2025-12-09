use flutter_rust_bridge::frb;
use sea_orm::{EntityTrait, QueryFilter, ColumnTrait, ActiveModelTrait, Set};
use chrono::{Utc, Duration};
use tokio::fs;
use crate::database::{self, entities::image_cache};
use crate::api::module_api;

/// 获取缓存的图片文件路径
#[frb]
pub async fn get_cached_image(module_id: String, url: String) -> anyhow::Result<Option<String>> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    let cache_key = image_cache::Model::create_cache_key(&module_id, &url);
    
    // 查找缓存记录
    let cache = image_cache::Entity::find_by_id(&cache_key)
        .one(&*conn)
        .await?;
    
    if let Some(cache) = cache {
        // 检查是否过期
        let now = Utc::now().naive_utc();
        if cache.expire_at > now {
            // 检查文件是否存在
            if fs::metadata(&cache.file_path).await.is_ok() {
                return Ok(Some(cache.file_path));
            } else {
                // 文件不存在，删除缓存记录
                let _ = image_cache::Entity::delete_by_id(&cache_key)
                    .exec(&*conn)
                    .await;
            }
        } else {
            // 已过期，删除缓存记录和文件
            let _ = fs::remove_file(&cache.file_path).await;
            let _ = image_cache::Entity::delete_by_id(&cache_key)
                .exec(&*conn)
                .await;
        }
    }
    
    Ok(None)
}

/// 保存图片到缓存
#[frb]
pub async fn save_image_to_cache(
    module_id: String,
    url: String,
    file_path: String,
    content_type: String,
    file_size: i64,
    expire_days: Option<i64>, // 过期天数，默认 30 天
) -> anyhow::Result<()> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    let cache_key = image_cache::Model::create_cache_key(&module_id, &url);
    let now = Utc::now().naive_utc();
    let expire_days = expire_days.unwrap_or(30);
    let expire_at = now + Duration::days(expire_days);
    
    // 检查是否已存在
    let existing = image_cache::Entity::find_by_id(&cache_key)
        .one(&*conn)
        .await?;
    
    if existing.is_some() {
        // 更新
        let active_model = image_cache::ActiveModel {
            cache_key: Set(cache_key),
            module_id: Set(module_id),
            url: Set(url),
            file_path: Set(file_path),
            content_type: Set(content_type),
            file_size: Set(file_size),
            expire_at: Set(expire_at),
            created_at: sea_orm::ActiveValue::NotSet,
        };
        active_model.update(&*conn).await?;
    } else {
        // 插入
        let active_model = image_cache::ActiveModel {
            cache_key: Set(cache_key),
            module_id: Set(module_id),
            url: Set(url),
            file_path: Set(file_path),
            content_type: Set(content_type),
            file_size: Set(file_size),
            expire_at: Set(expire_at),
            created_at: Set(now),
        };
        active_model.insert(&*conn).await?;
    }
    
    Ok(())
}

/// 清除指定模块的图片缓存
#[frb]
pub async fn clear_image_cache_by_module(module_id: String) -> anyhow::Result<u64> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    
    // 查找所有缓存记录
    let caches = image_cache::Entity::find()
        .filter(image_cache::Column::ModuleId.eq(&module_id))
        .all(&*conn)
        .await?;
    
    // 删除文件
    for cache in &caches {
        let _ = fs::remove_file(&cache.file_path).await;
    }
    
    // 删除数据库记录
    let result = image_cache::Entity::delete_many()
        .filter(image_cache::Column::ModuleId.eq(&module_id))
        .exec(&*conn)
        .await?;
    
    Ok(result.rows_affected)
}

/// 清除所有图片缓存
#[frb]
pub async fn clear_all_image_cache() -> anyhow::Result<u64> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    
    // 查找所有缓存记录
    let caches = image_cache::Entity::find()
        .all(&*conn)
        .await?;
    
    // 删除文件
    for cache in &caches {
        let _ = fs::remove_file(&cache.file_path).await;
    }
    
    // 删除数据库记录
    let result = image_cache::Entity::delete_many()
        .exec(&*conn)
        .await?;
    
    Ok(result.rows_affected)
}

/// 清除过期的图片缓存
#[frb]
pub async fn clear_expired_image_cache() -> anyhow::Result<u64> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    let now = Utc::now().naive_utc();
    
    // 查找所有过期的缓存记录
    let caches = image_cache::Entity::find()
        .filter(image_cache::Column::ExpireAt.lt(now))
        .all(&*conn)
        .await?;
    
    // 删除文件
    for cache in &caches {
        let _ = fs::remove_file(&cache.file_path).await;
    }
    
    // 删除数据库记录
    let result = image_cache::Entity::delete_many()
        .filter(image_cache::Column::ExpireAt.lt(now))
        .exec(&*conn)
        .await?;
    
    Ok(result.rows_affected)
}

/// 获取缓存统计信息
#[frb]
pub async fn get_image_cache_stats() -> anyhow::Result<ImageCacheStats> {
    let db = database::get_database()
        .ok_or_else(|| anyhow::anyhow!("Database not initialized"))?;
    
    let conn = db.read().await;
    let now = Utc::now().naive_utc();
    
    // 获取所有缓存记录
    let all_caches = image_cache::Entity::find()
        .all(&*conn)
        .await?;
    
    let mut total_size = 0u64;
    let mut expired_count = 0u64;
    let mut valid_count = 0u64;
    
    for cache in &all_caches {
        total_size += cache.file_size as u64;
        if cache.expire_at <= now {
            expired_count += 1;
        } else {
            valid_count += 1;
        }
    }
    
    Ok(ImageCacheStats {
        total_count: all_caches.len() as u64,
        valid_count,
        expired_count,
        total_size,
    })
}

/// 缓存统计信息
#[derive(Debug, Clone)]
pub struct ImageCacheStats {
    pub total_count: u64,
    pub valid_count: u64,
    pub expired_count: u64,
    pub total_size: u64, // 字节
}

/// 使用模块处理图片
/// 如果模块有 processImage 函数，则调用它处理图片
/// 参数：
/// - module_id: 模块 ID
/// - image_data_base64: 图片数据的 base64 编码
/// - params_json: 额外的参数（JSON 格式），例如 {"chapterId": "123", "imageName": "001.jpg"}
/// 返回：处理后的图片数据（base64 编码），如果模块没有 processImage 函数或处理失败，返回原始数据
#[frb]
pub async fn process_image_with_module(
    module_id: String,
    image_data_base64: String,
    params_json: String,
) -> anyhow::Result<String> {
    // 尝试调用模块的 processImage 函数
    let args = serde_json::json!({
        "imageData": image_data_base64,
        "params": serde_json::from_str::<serde_json::Value>(&params_json).unwrap_or(serde_json::json!({}))
    });
    
    match module_api::call_module_function(
        module_id.clone(),
        "processImage".to_string(),
        serde_json::to_string(&args)?,
    ).await {
        Ok(result) => {
            // 解析返回结果
            let result_json: serde_json::Value = serde_json::from_str(&result)?;
            if let Some(processed_data) = result_json.get("imageData").and_then(|v| v.as_str()) {
                Ok(processed_data.to_string())
            } else {
                // 如果返回格式不对，返回原始数据
                Ok(image_data_base64)
            }
        }
        Err(_) => {
            // 模块没有 processImage 函数或调用失败，返回原始数据
            Ok(image_data_base64)
        }
    }
}

