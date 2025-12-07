use sha2::{Sha256, Sha512, Digest as ShaDigest};
use base64::{Engine as _, engine::general_purpose};
use aes::Aes256;
use aes::cipher::{BlockDecrypt, KeyInit, generic_array::GenericArray};
use hmac::Hmac;
use hmac::digest::Mac;

type HmacSha256 = Hmac<Sha256>;

/// 计算 MD5 哈希
pub fn md5_hash(data: &[u8]) -> String {
    let digest = md5::compute(data);
    format!("{:x}", digest)
}

/// 计算 MD5 哈希（字符串输入）
pub fn md5_string(data: &str) -> String {
    md5_hash(data.as_bytes())
}

/// 计算 SHA256 哈希
pub fn sha256_hash(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

/// 计算 SHA256 哈希（字符串输入）
pub fn sha256_string(data: &str) -> String {
    sha256_hash(data.as_bytes())
}

/// 计算 SHA512 哈希
pub fn sha512_hash(data: &[u8]) -> String {
    let mut hasher = Sha512::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

/// 计算 SHA512 哈希（字符串输入）
pub fn sha512_string(data: &str) -> String {
    sha512_hash(data.as_bytes())
}

/// Base64 编码
pub fn base64_encode(data: &[u8]) -> String {
    general_purpose::STANDARD.encode(data)
}

/// Base64 编码（字符串输入）
pub fn base64_encode_string(data: &str) -> String {
    base64_encode(data.as_bytes())
}

/// Base64 解码
pub fn base64_decode(data: &str) -> anyhow::Result<Vec<u8>> {
    general_purpose::STANDARD
        .decode(data)
        .map_err(|e| anyhow::anyhow!("Base64 decode error: {}", e))
}

/// Base64 解码为字符串
pub fn base64_decode_string(data: &str) -> anyhow::Result<String> {
    let bytes = base64_decode(data)?;
    String::from_utf8(bytes)
        .map_err(|e| anyhow::anyhow!("UTF-8 decode error: {}", e))
}

/// Hex 编码
pub fn hex_encode(data: &[u8]) -> String {
    hex::encode(data)
}

/// Hex 解码
pub fn hex_decode(data: &str) -> anyhow::Result<Vec<u8>> {
    hex::decode(data)
        .map_err(|e| anyhow::anyhow!("Hex decode error: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_md5() {
        assert_eq!(md5_string("hello"), "5d41402abc4b2a76b9719d911017c592");
    }

    #[test]
    fn test_sha256() {
        assert_eq!(
            sha256_string("hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
    }

    #[test]
    fn test_base64() {
        let encoded = base64_encode_string("hello");
        assert_eq!(encoded, "aGVsbG8=");
        let decoded = base64_decode_string(&encoded).unwrap();
        assert_eq!(decoded, "hello");
    }

    #[test]
    fn test_hex() {
        let encoded = hex_encode(b"hello");
        assert_eq!(encoded, "68656c6c6f");
        let decoded = hex_decode(&encoded).unwrap();
        assert_eq!(decoded, b"hello");
    }
}

/// AES-256-ECB 解密
/// key 必须是 32 字节（256位）
pub fn aes_ecb_decrypt(data: &[u8], key: &[u8]) -> anyhow::Result<Vec<u8>> {
    if key.len() != 32 {
        return Err(anyhow::anyhow!("AES-256 requires 32 byte key, got {}", key.len()));
    }
    
    if data.len() % 16 != 0 {
        return Err(anyhow::anyhow!("Data length must be multiple of 16 bytes"));
    }
    
    let key_arr = GenericArray::from_slice(key);
    let cipher = Aes256::new(key_arr);
    
    let mut result = Vec::with_capacity(data.len());
    
    // 按 16 字节块解密
    for chunk in data.chunks(16) {
        let mut block = GenericArray::clone_from_slice(chunk);
        cipher.decrypt_block(&mut block);
        result.extend_from_slice(&block);
    }
    
    // 移除 PKCS7 填充
    if let Some(&pad_len) = result.last() {
        let pad_len = pad_len as usize;
        if pad_len > 0 && pad_len <= 16 && result.len() >= pad_len {
            // 验证填充
            let valid_padding = result[result.len() - pad_len..]
                .iter()
                .all(|&b| b as usize == pad_len);
            if valid_padding {
                result.truncate(result.len() - pad_len);
            }
        }
    }
    
    Ok(result)
}

/// AES-256-ECB 解密（Base64 编码输入，返回字符串）
pub fn aes_ecb_decrypt_base64(data: &str, key: &str) -> anyhow::Result<String> {
    let encrypted = base64_decode(data)?;
    let key_bytes = key.as_bytes();
    let decrypted = aes_ecb_decrypt(&encrypted, key_bytes)?;
    String::from_utf8(decrypted)
        .map_err(|e| anyhow::anyhow!("UTF-8 decode error: {}", e))
}

/// HMAC-SHA256 签名
pub fn hmac_sha256(data: &str, key: &str) -> String {
    let mut mac = <HmacSha256 as Mac>::new_from_slice(key.as_bytes())
        .expect("HMAC can take key of any size");
    mac.update(data.as_bytes());
    let result = mac.finalize();
    hex::encode(result.into_bytes())
}

#[cfg(test)]
mod hmac_tests {
    use super::*;

    #[test]
    fn test_hmac_sha256() {
        // 测试 HMAC-SHA256
        let result = hmac_sha256("hello", "secret");
        assert!(!result.is_empty());
        assert_eq!(result.len(), 64); // SHA256 输出 32 字节 = 64 hex 字符
    }
}
