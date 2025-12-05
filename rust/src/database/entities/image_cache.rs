use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use chrono::NaiveDateTime;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "image_cache")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub cache_key: String,    // URL hash
    pub module_id: String,
    pub url: String,
    pub file_path: String,    // 本地文件路径
    pub content_type: String,
    pub file_size: i64,
    pub expire_at: NaiveDateTime,
    pub created_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}

impl Model {
    pub fn create_cache_key(module_id: &str, url: &str) -> String {
        let digest = md5::compute(format!("{}:{}", module_id, url));
        format!("{:x}", digest)
    }
}
