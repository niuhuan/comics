use serde::{Deserialize, Serialize};

/// 模块信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleInfo {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    pub enabled: bool,
}

/// 漫画分类
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Category {
    pub id: String,
    pub name: String,
    pub cover: Option<String>,
}

/// 漫画基本信息（列表项）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComicSimple {
    pub id: String,
    pub title: String,
    pub cover: String,
    pub author: Option<String>,
    pub update_info: Option<String>,
}

/// 漫画详情
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComicDetail {
    pub id: String,
    pub title: String,
    pub cover: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub status: Option<String>,
    pub tags: Vec<String>,
    pub chapters: Vec<Chapter>,
    pub update_time: Option<String>,
}

/// 章节信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chapter {
    pub id: String,
    pub title: String,
    pub update_time: Option<String>,
}

/// 章节图片列表
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterImages {
    pub chapter_id: String,
    pub images: Vec<ImageInfo>,
}

/// 图片信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageInfo {
    pub url: String,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub headers: Option<std::collections::HashMap<String, String>>,
}

/// 分页信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageInfo {
    pub page: i32,
    pub page_size: i32,
    pub total: Option<i32>,
    pub has_more: bool,
}

/// 漫画列表响应
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComicListResponse {
    pub comics: Vec<ComicSimple>,
    pub page_info: PageInfo,
}

/// 搜索参数
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchParams {
    pub keyword: String,
    pub page: i32,
    pub page_size: i32,
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
