use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 模块信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleInfo {
    pub id: String,
    pub name: String,
    pub version: String,
    pub author: String,
    pub description: String,
    pub icon: Option<String>,
    pub enabled: bool,
}

/// 远程图片信息 (参考 pikapika RemoteImageInfo)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteImageInfo {
    pub original_name: String,
    pub path: String,
    pub file_server: String,
    /// 可选的请求头
    #[serde(default)]
    pub headers: HashMap<String, String>,
}

impl RemoteImageInfo {
    /// 从单个URL创建
    pub fn from_url(url: impl Into<String>) -> Self {
        let url = url.into();
        Self {
            original_name: String::new(),
            path: url.clone(),
            file_server: String::new(),
            headers: HashMap::new(),
        }
    }
    
    /// 从URL和headers创建
    pub fn from_url_with_headers(url: impl Into<String>, headers: HashMap<String, String>) -> Self {
        let url = url.into();
        Self {
            original_name: String::new(),
            path: url.clone(),
            file_server: String::new(),
            headers,
        }
    }
    
    /// 从服务器和路径创建
    pub fn from_server_path(file_server: impl Into<String>, path: impl Into<String>) -> Self {
        Self {
            original_name: String::new(),
            path: path.into(),
            file_server: file_server.into(),
            headers: HashMap::new(),
        }
    }
    
    /// 转换为完整URL
    pub fn to_url(&self) -> String {
        if self.file_server.is_empty() {
            self.path.clone()
        } else if self.path.starts_with("http://") || self.path.starts_with("https://") {
            self.path.clone()
        } else {
            format!("{}/static/{}", self.file_server, self.path)
        }
    }
}

impl Default for RemoteImageInfo {
    fn default() -> Self {
        Self {
            original_name: String::new(),
            path: String::new(),
            file_server: String::new(),
            headers: HashMap::new(),
        }
    }
}

/// 分类 (参考 pikapika Category)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Category {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub description: String,
    pub thumb: Option<RemoteImageInfo>,
    #[serde(default)]
    pub is_web: bool,
    #[serde(default = "default_true")]
    pub active: bool,
    pub link: Option<String>,
}

fn default_true() -> bool { true }

/// 分页信息 (参考 pikapika Page)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageInfo {
    pub total: i32,
    pub limit: i32,
    pub page: i32,
    pub pages: i32,
}

impl PageInfo {
    pub fn new(page: i32, limit: i32, total: i32) -> Self {
        let pages = if total <= 0 { 0 } else { (total + limit - 1) / limit };
        Self { total, limit, page, pages }
    }
    
    pub fn empty() -> Self {
        Self { total: 0, limit: 20, page: 1, pages: 0 }
    }
    
    pub fn has_next(&self) -> bool {
        self.page < self.pages
    }
}

/// 漫画简略信息 (参考 pikapika ComicSimple)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComicSimple {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub author: String,
    #[serde(default)]
    pub pages_count: i32,
    #[serde(default)]
    pub eps_count: i32,
    #[serde(default)]
    pub finished: bool,
    #[serde(default)]
    pub categories: Vec<String>,
    pub thumb: RemoteImageInfo,
    #[serde(default)]
    pub likes_count: i32,
}

/// 漫画详情 (参考 pikapika ComicInfo)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComicDetail {
    // 基础信息 (来自 ComicSimple)
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub author: String,
    #[serde(default)]
    pub pages_count: i32,
    #[serde(default)]
    pub eps_count: i32,
    #[serde(default)]
    pub finished: bool,
    #[serde(default)]
    pub categories: Vec<String>,
    pub thumb: RemoteImageInfo,
    #[serde(default)]
    pub likes_count: i32,
    // 详情信息
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub chinese_team: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub updated_at: String,
    #[serde(default)]
    pub created_at: String,
    #[serde(default = "default_true")]
    pub allow_download: bool,
    #[serde(default)]
    pub views_count: i32,
    #[serde(default)]
    pub is_favourite: bool,
    #[serde(default)]
    pub is_liked: bool,
    #[serde(default)]
    pub comments_count: i32,
}

/// 章节 (参考 pikapika Ep)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ep {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub order: i32,
    #[serde(default)]
    pub updated_at: String,
}

/// 章节分页 (参考 pikapika EpPage)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EpPage {
    #[serde(flatten)]
    pub page_info: PageInfo,
    pub docs: Vec<Ep>,
}

/// 漫画图片 (参考 pikapika Picture)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Picture {
    pub id: String,
    pub media: RemoteImageInfo,
}

/// 图片分页 (参考 pikapika PicturePage)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PicturePage {
    #[serde(flatten)]
    pub page_info: PageInfo,
    pub docs: Vec<Picture>,
}

/// 漫画列表分页 (参考 pikapika ComicsPage)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComicsPage {
    #[serde(flatten)]
    pub page_info: PageInfo,
    pub docs: Vec<ComicSimple>,
}

/// 搜索结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    #[serde(flatten)]
    pub page_info: PageInfo,
    pub docs: Vec<ComicSimple>,
    #[serde(default)]
    pub search_query: String,
}

/// 排序方式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SortOption {
    pub value: String,
    pub name: String,
}

impl SortOption {
    pub fn new(value: impl Into<String>, name: impl Into<String>) -> Self {
        Self { value: value.into(), name: name.into() }
    }
}

/// 模块调用结果
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ModuleResult<T> {
    Success { data: T },
    Error { message: String, code: Option<String> },
}

impl<T> ModuleResult<T> {
    pub fn success(data: T) -> Self {
        Self::Success { data }
    }
    
    pub fn error(message: impl Into<String>) -> Self {
        Self::Error {
            message: message.into(),
            code: None,
        }
    }
    
    pub fn error_with_code(message: impl Into<String>, code: impl Into<String>) -> Self {
        Self::Error {
            message: message.into(),
            code: Some(code.into()),
        }
    }
    
    pub fn into_result(self) -> anyhow::Result<T> {
        match self {
            Self::Success { data } => Ok(data),
            Self::Error { message, .. } => Err(anyhow::anyhow!(message)),
        }
    }
}
