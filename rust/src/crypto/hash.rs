use sha2::{Sha256, Sha512, Digest as ShaDigest};
use base64::{Engine as _, engine::general_purpose};

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
