use rquickjs::{Ctx, Function, Object};
use anyhow::Result;
use scraper::{Html, Selector};
use serde_json::{json, Value as JsonValue};

/// 注册 html 解析对象到 JS 全局
pub fn register(ctx: &Ctx<'_>) -> Result<()> {
    let globals = ctx.globals();
    
    let html_obj = Object::new(ctx.clone())?;
    
    // html.select(htmlString, selector) -> Array<{text, html, attrs}>
    // 使用 CSS 选择器查询元素
    html_obj.set("select", Function::new(ctx.clone(), |html_str: String, selector: String| -> String {
        match select_elements(&html_str, &selector) {
            Ok(result) => result,
            Err(e) => {
                tracing::error!("[JS HTML] Select error: {}", e);
                "[]".to_string()
            }
        }
    })?)?;
    
    // html.selectOne(htmlString, selector) -> {text, html, attrs} | null
    // 查询单个元素
    html_obj.set("selectOne", Function::new(ctx.clone(), |html_str: String, selector: String| -> String {
        match select_one(&html_str, &selector) {
            Ok(result) => result,
            Err(e) => {
                tracing::error!("[JS HTML] SelectOne error: {}", e);
                "null".to_string()
            }
        }
    })?)?;
    
    // html.attr(htmlString, selector, attrName) -> string | null
    // 获取元素属性
    html_obj.set("attr", Function::new(ctx.clone(), |html_str: String, selector: String, attr: String| -> String {
        match get_attr(&html_str, &selector, &attr) {
            Ok(Some(value)) => value,
            Ok(None) => String::new(),
            Err(e) => {
                tracing::error!("[JS HTML] Attr error: {}", e);
                String::new()
            }
        }
    })?)?;
    
    // html.attrs(htmlString, selector, attrName) -> Array<string>
    // 获取所有匹配元素的属性
    html_obj.set("attrs", Function::new(ctx.clone(), |html_str: String, selector: String, attr: String| -> String {
        match get_attrs(&html_str, &selector, &attr) {
            Ok(values) => serde_json::to_string(&values).unwrap_or_else(|_| "[]".to_string()),
            Err(e) => {
                tracing::error!("[JS HTML] Attrs error: {}", e);
                "[]".to_string()
            }
        }
    })?)?;
    
    // html.text(htmlString, selector) -> string
    // 获取元素文本内容
    html_obj.set("text", Function::new(ctx.clone(), |html_str: String, selector: String| -> String {
        match get_text(&html_str, &selector) {
            Ok(Some(value)) => value,
            Ok(None) => String::new(),
            Err(e) => {
                tracing::error!("[JS HTML] Text error: {}", e);
                String::new()
            }
        }
    })?)?;
    
    // html.texts(htmlString, selector) -> Array<string>
    // 获取所有匹配元素的文本
    html_obj.set("texts", Function::new(ctx.clone(), |html_str: String, selector: String| -> String {
        match get_texts(&html_str, &selector) {
            Ok(values) => serde_json::to_string(&values).unwrap_or_else(|_| "[]".to_string()),
            Err(e) => {
                tracing::error!("[JS HTML] Texts error: {}", e);
                "[]".to_string()
            }
        }
    })?)?;
    
    // html.innerHTML(htmlString, selector) -> string
    // 获取元素内部 HTML
    html_obj.set("innerHTML", Function::new(ctx.clone(), |html_str: String, selector: String| -> String {
        match get_inner_html(&html_str, &selector) {
            Ok(Some(value)) => value,
            Ok(None) => String::new(),
            Err(e) => {
                tracing::error!("[JS HTML] InnerHTML error: {}", e);
                String::new()
            }
        }
    })?)?;
    
    globals.set("__html__", html_obj)?;
    
    tracing::debug!("[JS HTML] HTML bindings registered");
    
    Ok(())
}

/// 使用 CSS 选择器查询多个元素
fn select_elements(html_str: &str, selector_str: &str) -> Result<String> {
    let document = Html::parse_document(html_str);
    let selector = Selector::parse(selector_str)
        .map_err(|e| anyhow::anyhow!("Invalid selector: {:?}", e))?;
    
    let mut results: Vec<JsonValue> = Vec::new();
    
    for element in document.select(&selector) {
        let mut attrs = serde_json::Map::new();
        for (name, value) in element.value().attrs() {
            attrs.insert(name.to_string(), json!(value));
        }
        
        results.push(json!({
            "text": element.text().collect::<Vec<_>>().join(""),
            "html": element.inner_html(),
            "attrs": attrs
        }));
    }
    
    Ok(serde_json::to_string(&results)?)
}

/// 使用 CSS 选择器查询单个元素
fn select_one(html_str: &str, selector_str: &str) -> Result<String> {
    let document = Html::parse_document(html_str);
    let selector = Selector::parse(selector_str)
        .map_err(|e| anyhow::anyhow!("Invalid selector: {:?}", e))?;
    
    if let Some(element) = document.select(&selector).next() {
        let mut attrs = serde_json::Map::new();
        for (name, value) in element.value().attrs() {
            attrs.insert(name.to_string(), json!(value));
        }
        
        let result = json!({
            "text": element.text().collect::<Vec<_>>().join(""),
            "html": element.inner_html(),
            "attrs": attrs
        });
        
        Ok(serde_json::to_string(&result)?)
    } else {
        Ok("null".to_string())
    }
}

/// 获取元素属性
fn get_attr(html_str: &str, selector_str: &str, attr_name: &str) -> Result<Option<String>> {
    let document = Html::parse_document(html_str);
    let selector = Selector::parse(selector_str)
        .map_err(|e| anyhow::anyhow!("Invalid selector: {:?}", e))?;
    
    if let Some(element) = document.select(&selector).next() {
        Ok(element.value().attr(attr_name).map(|s| s.to_string()))
    } else {
        Ok(None)
    }
}

/// 获取所有匹配元素的属性
fn get_attrs(html_str: &str, selector_str: &str, attr_name: &str) -> Result<Vec<String>> {
    let document = Html::parse_document(html_str);
    let selector = Selector::parse(selector_str)
        .map_err(|e| anyhow::anyhow!("Invalid selector: {:?}", e))?;
    
    let values: Vec<String> = document
        .select(&selector)
        .filter_map(|el| el.value().attr(attr_name).map(|s| s.to_string()))
        .collect();
    
    Ok(values)
}

/// 获取元素文本
fn get_text(html_str: &str, selector_str: &str) -> Result<Option<String>> {
    let document = Html::parse_document(html_str);
    let selector = Selector::parse(selector_str)
        .map_err(|e| anyhow::anyhow!("Invalid selector: {:?}", e))?;
    
    if let Some(element) = document.select(&selector).next() {
        Ok(Some(element.text().collect::<Vec<_>>().join("")))
    } else {
        Ok(None)
    }
}

/// 获取所有匹配元素的文本
fn get_texts(html_str: &str, selector_str: &str) -> Result<Vec<String>> {
    let document = Html::parse_document(html_str);
    let selector = Selector::parse(selector_str)
        .map_err(|e| anyhow::anyhow!("Invalid selector: {:?}", e))?;
    
    let values: Vec<String> = document
        .select(&selector)
        .map(|el| el.text().collect::<Vec<_>>().join(""))
        .collect();
    
    Ok(values)
}

/// 获取元素内部 HTML
fn get_inner_html(html_str: &str, selector_str: &str) -> Result<Option<String>> {
    let document = Html::parse_document(html_str);
    let selector = Selector::parse(selector_str)
        .map_err(|e| anyhow::anyhow!("Invalid selector: {:?}", e))?;
    
    if let Some(element) = document.select(&selector).next() {
        Ok(Some(element.inner_html()))
    } else {
        Ok(None)
    }
}
