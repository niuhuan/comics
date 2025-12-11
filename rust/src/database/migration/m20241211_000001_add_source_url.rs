use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // 添加 source_url 字段到 module_info 表
        manager
            .alter_table(
                Table::alter()
                    .table(ModuleInfo::Table)
                    .add_column(ColumnDef::new(ModuleInfo::SourceUrl).string().null())
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .alter_table(
                Table::alter()
                    .table(ModuleInfo::Table)
                    .drop_column(ModuleInfo::SourceUrl)
                    .to_owned(),
            )
            .await
    }
}

#[derive(Iden)]
enum ModuleInfo {
    Table,
    SourceUrl,
}
