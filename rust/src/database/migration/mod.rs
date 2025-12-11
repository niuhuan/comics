pub use sea_orm_migration::prelude::*;

mod m20241205_000001_create_tables;
mod m20241211_000001_add_source_url;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(m20241205_000001_create_tables::Migration),
            Box::new(m20241211_000001_add_source_url::Migration),
        ]
    }
}

pub async fn run_migrations(conn: &sea_orm::DatabaseConnection) -> anyhow::Result<()> {
    Migrator::up(conn, None).await?;
    tracing::info!("Database migrations completed");
    Ok(())
}
