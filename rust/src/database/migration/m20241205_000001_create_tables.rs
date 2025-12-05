use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        // Properties 表
        manager.create_table(
            Table::create()
                .table(Properties::Table)
                .if_not_exists()
                .col(ColumnDef::new(Properties::Id).string().not_null().primary_key())
                .col(ColumnDef::new(Properties::ModuleId).string().not_null())
                .col(ColumnDef::new(Properties::Key).string().not_null())
                .col(ColumnDef::new(Properties::Value).text().not_null())
                .col(ColumnDef::new(Properties::CreatedAt).date_time().not_null())
                .col(ColumnDef::new(Properties::UpdatedAt).date_time().not_null())
                .to_owned()
        ).await?;

        manager.create_index(
            Index::create()
                .name("idx_properties_module_id")
                .table(Properties::Table)
                .col(Properties::ModuleId)
                .to_owned()
        ).await?;

        // ModuleInfo 表
        manager.create_table(
            Table::create()
                .table(ModuleInfo::Table)
                .if_not_exists()
                .col(ColumnDef::new(ModuleInfo::Id).string().not_null().primary_key())
                .col(ColumnDef::new(ModuleInfo::Name).string().not_null())
                .col(ColumnDef::new(ModuleInfo::Version).string().not_null())
                .col(ColumnDef::new(ModuleInfo::Description).text().not_null())
                .col(ColumnDef::new(ModuleInfo::ScriptPath).string().not_null())
                .col(ColumnDef::new(ModuleInfo::Enabled).boolean().not_null().default(true))
                .col(ColumnDef::new(ModuleInfo::CreatedAt).date_time().not_null())
                .col(ColumnDef::new(ModuleInfo::UpdatedAt).date_time().not_null())
                .to_owned()
        ).await?;

        // WebCache 表
        manager.create_table(
            Table::create()
                .table(WebCache::Table)
                .if_not_exists()
                .col(ColumnDef::new(WebCache::CacheKey).string().not_null().primary_key())
                .col(ColumnDef::new(WebCache::ModuleId).string().not_null())
                .col(ColumnDef::new(WebCache::Url).text().not_null())
                .col(ColumnDef::new(WebCache::ResponseBody).text().not_null())
                .col(ColumnDef::new(WebCache::ContentType).string().not_null())
                .col(ColumnDef::new(WebCache::ExpireAt).date_time().not_null())
                .col(ColumnDef::new(WebCache::CreatedAt).date_time().not_null())
                .to_owned()
        ).await?;

        manager.create_index(
            Index::create()
                .name("idx_web_cache_module_id")
                .table(WebCache::Table)
                .col(WebCache::ModuleId)
                .to_owned()
        ).await?;

        // ImageCache 表
        manager.create_table(
            Table::create()
                .table(ImageCache::Table)
                .if_not_exists()
                .col(ColumnDef::new(ImageCache::CacheKey).string().not_null().primary_key())
                .col(ColumnDef::new(ImageCache::ModuleId).string().not_null())
                .col(ColumnDef::new(ImageCache::Url).text().not_null())
                .col(ColumnDef::new(ImageCache::FilePath).string().not_null())
                .col(ColumnDef::new(ImageCache::ContentType).string().not_null())
                .col(ColumnDef::new(ImageCache::FileSize).big_integer().not_null())
                .col(ColumnDef::new(ImageCache::ExpireAt).date_time().not_null())
                .col(ColumnDef::new(ImageCache::CreatedAt).date_time().not_null())
                .to_owned()
        ).await?;

        manager.create_index(
            Index::create()
                .name("idx_image_cache_module_id")
                .table(ImageCache::Table)
                .col(ImageCache::ModuleId)
                .to_owned()
        ).await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager.drop_table(Table::drop().table(Properties::Table).to_owned()).await?;
        manager.drop_table(Table::drop().table(ModuleInfo::Table).to_owned()).await?;
        manager.drop_table(Table::drop().table(WebCache::Table).to_owned()).await?;
        manager.drop_table(Table::drop().table(ImageCache::Table).to_owned()).await?;
        Ok(())
    }
}

#[derive(Iden)]
enum Properties {
    Table,
    Id,
    ModuleId,
    Key,
    Value,
    CreatedAt,
    UpdatedAt,
}

#[derive(Iden)]
enum ModuleInfo {
    Table,
    Id,
    Name,
    Version,
    Description,
    ScriptPath,
    Enabled,
    CreatedAt,
    UpdatedAt,
}

#[derive(Iden)]
enum WebCache {
    Table,
    CacheKey,
    ModuleId,
    Url,
    ResponseBody,
    ContentType,
    ExpireAt,
    CreatedAt,
}

#[derive(Iden)]
enum ImageCache {
    Table,
    CacheKey,
    ModuleId,
    Url,
    FilePath,
    ContentType,
    FileSize,
    ExpireAt,
    CreatedAt,
}
