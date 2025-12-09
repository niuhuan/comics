use rquickjs::{Ctx, Function, Object};
use anyhow::Result;

use crate::api::image_api;

/// 注册 image 对象到 JS 全局
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    let image_obj = Object::new(ctx.clone())?;
    
    // image.getInfo(imageDataBase64) -> JSON string with {width, height, format}
    image_obj.set("getInfo", Function::new(ctx.clone(), |image_data_base64: String| -> String {
        match image_api::get_image_info(image_data_base64) {
            Ok(info) => info,
            Err(e) => {
                tracing::error!("[JS Image] Failed to get image info: {}", e);
                serde_json::json!({
                    "error": format!("Failed to get image info: {}", e)
                }).to_string()
            }
        }
    })?)?;
    
    // image.rearrangeRows(imageDataBase64, rows) -> base64 encoded PNG
    image_obj.set("rearrangeRows", Function::new(ctx.clone(), |image_data_base64: String, rows: u32| -> String {
        match image_api::rearrange_image_rows(image_data_base64, rows) {
            Ok(result) => result,
            Err(e) => {
                tracing::error!("[JS Image] Failed to rearrange image rows: {}", e);
                String::new()
            }
        }
    })?)?;
    
    globals.set("__image__", image_obj)?;
    
    Ok(())
}

