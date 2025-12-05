use sea_orm::entity::prelude::*;
use serde::{Deserialize, Serialize};
use chrono::NaiveDateTime;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize, Deserialize)]
#[sea_orm(table_name = "properties")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: String,  // module_id:key 组合
    pub module_id: String,
    pub key: String,
    pub value: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}

impl Model {
    pub fn create_id(module_id: &str, key: &str) -> String {
        format!("{}:{}", module_id, key)
    }
}
