use std::path::Path;
use anyhow::Result;
use serde::{Deserialize, Serialize};

/// 模块元信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleMetadata {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
}

/// 模块加载器
pub struct ModuleLoader {
    modules_dir: std::path::PathBuf,
}

impl ModuleLoader {
    pub fn new(modules_dir: &Path) -> Self {
        Self {
            modules_dir: modules_dir.to_path_buf(),
        }
    }

    /// 从文件加载模块脚本
    pub async fn load_script(&self, module_id: &str) -> Result<String> {
        let script_path = self.modules_dir.join(format!("{}.js", module_id));
        
        if !script_path.exists() {
            return Err(anyhow::anyhow!("Module script not found: {}", module_id));
        }
        
        let script = tokio::fs::read_to_string(&script_path).await?;
        Ok(script)
    }

    /// 从脚本中提取模块元信息
    pub fn extract_metadata(&self, script: &str) -> Result<ModuleMetadata> {
        // 查找模块导出的 metadata 对象
        // 期望格式:
        // const moduleInfo = {
        //   id: "module_id",
        //   name: "Module Name",
        //   version: "1.0.0",
        //   description: "Description"
        // };
        
        // 使用正则或简单解析提取元信息
        // 这里使用简化的方式，实际可以用 JS 运行时执行获取
        
        // 查找 moduleInfo 或 module.exports
        let id = self.extract_field(script, "id")?;
        let name = self.extract_field(script, "name")?;
        let version = self.extract_field(script, "version")?;
        let description = self.extract_field(script, "description").unwrap_or_default();
        
        Ok(ModuleMetadata {
            id,
            name,
            version,
            description,
        })
    }

    fn extract_field(&self, script: &str, field: &str) -> Result<String> {
        // 简单的字段提取，查找 field: "value" 或 field: 'value'
        let patterns = [
            format!(r#"{}:\s*["']([^"']+)["']"#, field),
            format!(r#""{}":\s*["']([^"']+)["']"#, field),
        ];
        
        for pattern in &patterns {
            let re = regex::Regex::new(pattern)?;
            if let Some(captures) = re.captures(script) {
                if let Some(value) = captures.get(1) {
                    return Ok(value.as_str().to_string());
                }
            }
        }
        
        Err(anyhow::anyhow!("Field '{}' not found in module script", field))
    }

    /// 验证模块脚本
    pub fn validate_script(&self, script: &str) -> Result<()> {
        // 检查必要的导出函数
        let required_functions = ["getCategories", "getComicList", "getComicDetail", "getChapterImages"];
        
        for func in required_functions {
            if !script.contains(&format!("function {}", func)) && 
               !script.contains(&format!("{} =", func)) &&
               !script.contains(&format!("{}:", func)) {
                tracing::warn!("Module may be missing function: {}", func);
            }
        }
        
        // 检查元信息
        self.extract_metadata(script)?;
        
        Ok(())
    }

    /// 列出所有可用模块
    pub async fn list_modules(&self) -> Result<Vec<String>> {
        let mut modules = Vec::new();
        
        let mut entries = tokio::fs::read_dir(&self.modules_dir).await?;
        
        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            if path.extension().map_or(false, |ext| ext == "js") {
                if let Some(stem) = path.file_stem() {
                    modules.push(stem.to_string_lossy().to_string());
                }
            }
        }
        
        Ok(modules)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_metadata() {
        let script = r#"
            const moduleInfo = {
                id: "test_module",
                name: "Test Module",
                version: "1.0.0",
                description: "A test module"
            };
        "#;
        
        let loader = ModuleLoader::new(Path::new("/tmp"));
        let metadata = loader.extract_metadata(script).unwrap();
        
        assert_eq!(metadata.id, "test_module");
        assert_eq!(metadata.name, "Test Module");
        assert_eq!(metadata.version, "1.0.0");
    }
}
