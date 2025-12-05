use flutter_rust_bridge::frb;

use crate::crypto;

/// MD5 哈希
#[frb(sync)]
pub fn crypto_md5(data: String) -> String {
    crypto::md5_string(&data)
}

/// SHA256 哈希
#[frb(sync)]
pub fn crypto_sha256(data: String) -> String {
    crypto::sha256_string(&data)
}

/// SHA512 哈希
#[frb(sync)]
pub fn crypto_sha512(data: String) -> String {
    crypto::sha512_string(&data)
}

/// Base64 编码
#[frb(sync)]
pub fn crypto_base64_encode(data: String) -> String {
    crypto::base64_encode_string(&data)
}

/// Base64 解码
#[frb(sync)]
pub fn crypto_base64_decode(data: String) -> anyhow::Result<String> {
    crypto::base64_decode_string(&data)
}

/// Hex 编码
#[frb(sync)]
pub fn crypto_hex_encode(data: String) -> String {
    crypto::hex_encode(data.as_bytes())
}

/// Hex 解码
#[frb(sync)]
pub fn crypto_hex_decode(data: String) -> anyhow::Result<String> {
    let bytes = crypto::hex_decode(&data)?;
    String::from_utf8(bytes)
        .map_err(|e| anyhow::anyhow!("UTF-8 decode error: {}", e))
}

/// MD5 哈希（字节数组）
#[frb(sync)]
pub fn crypto_md5_bytes(data: Vec<u8>) -> String {
    crypto::md5_hash(&data)
}

/// SHA256 哈希（字节数组）
#[frb(sync)]
pub fn crypto_sha256_bytes(data: Vec<u8>) -> String {
    crypto::sha256_hash(&data)
}
