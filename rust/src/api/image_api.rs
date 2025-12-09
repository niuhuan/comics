use flutter_rust_bridge::frb;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use image::RgbaImage;

/// 图片信息
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ImageInfo {
    pub width: u32,
    pub height: u32,
    pub format: String, // "png", "jpg", "gif", etc.
}

/// 获取图片信息（宽高、格式）
/// 参数：base64 编码的图片数据
/// 返回：图片信息 JSON 字符串
#[frb]
pub fn get_image_info(image_data_base64: String) -> anyhow::Result<String> {
    let image_bytes = BASE64.decode(&image_data_base64)?;
    let format = image::guess_format(&image_bytes)?;
    let img = image::load_from_memory(&image_bytes)?;
    
    let info = ImageInfo {
        width: img.width(),
        height: img.height(),
        format: format.extensions_str()[0].to_string(),
    };
    
    Ok(serde_json::to_string(&info)?)
}

/// 解码图片并重新排列行
/// 参数：
/// - image_data_base64: base64 编码的图片数据
/// - rows: 要分割的行数
/// 返回：重新排列后的图片数据（base64 编码的 PNG）
#[frb]
pub fn rearrange_image_rows(image_data_base64: String, rows: u32) -> anyhow::Result<String> {
    let image_bytes = BASE64.decode(&image_data_base64)?;
    let src = image::load_from_memory(&image_bytes)?;
    
    let width = src.width();
    let height = src.height();
    let remainder = height % rows;
    
    // 转换为 RGBA
    let src_rgba = src.to_rgba8();
    
    // 创建目标图像缓冲区
    let mut dst = RgbaImage::new(width, height);
    
    // 复制图像块的辅助函数
    let mut copy_image_block = |src_start_y: u32, dst_start_y: u32, block_height: u32| {
        for y in 0..block_height {
            for x in 0..width {
                let pixel = src_rgba.get_pixel(x, src_start_y + y);
                dst.put_pixel(x, dst_start_y + y, *pixel);
            }
        }
    };
    
    // 重新排列行（参考原版逻辑）
    for x in 0..rows {
        let mut copy_h = height / rows;
        let mut py = copy_h * x;
        let y = height - (copy_h * (x + 1)) - remainder;
        
        if x == 0 {
            copy_h += remainder;
        } else {
            py += remainder;
        }
        
        copy_image_block(y, py, copy_h);
    }
    
    // 编码为 PNG
    let mut png_data = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut png_data, width, height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header()?;
        writer.write_image_data(dst.as_raw())?;
    }
    
    // 转换为 base64
    let base64_result = BASE64.encode(&png_data);
    Ok(base64_result)
}

