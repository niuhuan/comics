use rquickjs::{Ctx, Function, Object, Value};
use anyhow::Result;

/// 注册 storage 对象到 JS 全局
/// 
/// storage 提供模块级别的键值存储，数据按 module_id 隔离
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    let storage = Object::new(ctx.clone())?;
    
    // 标记 storage 模块可用
    storage.set("_available", true)?;
    
    globals.set("__storage__", storage)?;
    
    // 注册辅助函数
    let storage_helper = r#"
        const storage = {
            async get(key) {
                return await __native_storage_get__(key);
            },
            async set(key, value) {
                return await __native_storage_set__(key, value);
            },
            async remove(key) {
                return await __native_storage_remove__(key);
            },
            async list(prefix = '') {
                return await __native_storage_list__(prefix);
            }
        };
    "#;
    
    let _: Value = ctx.eval(storage_helper)?;
    
    Ok(())
}
