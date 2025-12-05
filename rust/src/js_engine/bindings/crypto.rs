use rquickjs::{Ctx, Function, Object, Value};
use anyhow::Result;

use crate::crypto;

/// 注册 crypto 对象到 JS 全局
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    let crypto_obj = Object::new(ctx.clone())?;
    
    // crypto.md5(data) -> string
    crypto_obj.set("md5", Function::new(ctx.clone(), |data: String| -> String {
        crypto::md5_string(&data)
    })?)?;
    
    // crypto.sha256(data) -> string
    crypto_obj.set("sha256", Function::new(ctx.clone(), |data: String| -> String {
        crypto::sha256_string(&data)
    })?)?;
    
    // crypto.sha512(data) -> string
    crypto_obj.set("sha512", Function::new(ctx.clone(), |data: String| -> String {
        crypto::sha512_string(&data)
    })?)?;
    
    // crypto.base64Encode(data) -> string
    crypto_obj.set("base64Encode", Function::new(ctx.clone(), |data: String| -> String {
        crypto::base64_encode_string(&data)
    })?)?;
    
    // crypto.base64Decode(data) -> string
    crypto_obj.set("base64Decode", Function::new(ctx.clone(), |data: String| -> String {
        crypto::base64_decode_string(&data).unwrap_or_default()
    })?)?;
    
    // crypto.hexEncode(data) -> string
    crypto_obj.set("hexEncode", Function::new(ctx.clone(), |data: String| -> String {
        crypto::hex_encode(data.as_bytes())
    })?)?;
    
    // crypto.hexDecode(data) -> string
    crypto_obj.set("hexDecode", Function::new(ctx.clone(), |data: String| -> String {
        crypto::hex_decode(&data)
            .map(|bytes| String::from_utf8_lossy(&bytes).to_string())
            .unwrap_or_default()
    })?)?;
    
    globals.set("crypto", crypto_obj)?;
    
    Ok(())
}
