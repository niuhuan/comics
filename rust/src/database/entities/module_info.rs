use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use chrono::NaiveDateTime;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "module_info")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: String,           // 模块唯一ID
    pub name: String,         // 模块名称
    pub version: String,      // 版本号
    pub description: String,  // 描述
    pub script_path: String,  // JS 文件路径
    pub enabled: bool,        // 是否启用
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
