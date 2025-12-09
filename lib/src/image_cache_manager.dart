import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:comics/src/rust/api/image_cache_api.dart' as api;
import 'package:comics/src/rust/api/init.dart';

/// 图片缓存管理器
class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  /// 获取缓存的图片文件
  /// 如果缓存存在且未过期，返回本地文件路径
  /// 否则返回 null
  Future<String?> getCachedImagePath(String moduleId, String url) async {
    try {
      final cachedPath = await api.getCachedImage(moduleId: moduleId, url: url);
      if (cachedPath != null) {
        final file = File(cachedPath);
        if (await file.exists()) {
          return cachedPath;
        }
      }
    } catch (e) {
      debugPrint('Failed to get cached image: $e');
    }
    return null;
  }

  /// 下载并缓存图片
  /// 返回本地文件路径
  /// [processParams] 可选的图片处理参数（JSON 格式），例如 {"chapterId": "123", "imageName": "001.jpg"}
  Future<String?> cacheImage(
    String moduleId,
    String url, {
    Map<String, String>? headers,
    int expireDays = 30,
    Map<String, dynamic>? processParams,
  }) async {
    try {
      // 先检查缓存
      final cachedPath = await getCachedImagePath(moduleId, url);
      if (cachedPath != null) {
        return cachedPath;
      }

      // 下载图片
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to download image: ${response.statusCode}');
        return null;
      }

      // 获取图片数据
      var imageBytes = response.bodyBytes;

      // 如果提供了处理参数，尝试调用模块的图片处理函数
      if (processParams != null && processParams.isNotEmpty) {
        try {
          final imageDataBase64 = base64Encode(imageBytes);
          final paramsJson = jsonEncode(processParams);
          
          final processedDataBase64 = await api.processImageWithModule(
            moduleId: moduleId,
            imageDataBase64: imageDataBase64,
            paramsJson: paramsJson,
          );
          
          // 如果返回的数据与原始数据不同，说明处理成功
          if (processedDataBase64 != imageDataBase64) {
            imageBytes = base64Decode(processedDataBase64);
            debugPrint('Image processed by module: $moduleId');
          }
        } catch (e) {
          // 处理失败，使用原始数据
          debugPrint('Failed to process image with module: $e');
        }
      }

      // 获取缓存目录（使用 Rust 的缓存目录）
      final cacheDirPath = getCacheDir();
      if (cacheDirPath == null) {
        debugPrint('Cache directory not initialized');
        return null;
      }
      final cacheDir = Directory(path.join(cacheDirPath, 'images'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      // 生成文件名
      final cacheKey = _generateCacheKey(moduleId, url);
      final extension = _getExtensionFromUrl(url) ?? 'jpg';
      final fileName = '$cacheKey.$extension';
      final filePath = path.join(cacheDir.path, fileName);

      // 保存文件
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      // 保存缓存信息到数据库
      final contentType = response.headers['content-type'] ?? 'image/jpeg';
      final fileSize = await file.length();

      await api.saveImageToCache(
        moduleId: moduleId,
        url: url,
        filePath: filePath,
        contentType: contentType,
        fileSize: fileSize, // PlatformInt64 会自动转换
        expireDays: expireDays,
      );

      return filePath;
    } catch (e) {
      debugPrint('Failed to cache image: $e');
      return null;
    }
  }

  /// 清除指定模块的图片缓存
  Future<int> clearCacheByModule(String moduleId) async {
    try {
      final result = await api.clearImageCacheByModule(moduleId: moduleId);
      return result.toInt();
    } catch (e) {
      debugPrint('Failed to clear cache: $e');
      return 0;
    }
  }

  /// 清除所有图片缓存
  Future<int> clearAllCache() async {
    try {
      final result = await api.clearAllImageCache();
      return result.toInt();
    } catch (e) {
      debugPrint('Failed to clear all cache: $e');
      return 0;
    }
  }

  /// 清除过期的图片缓存
  Future<int> clearExpiredCache() async {
    try {
      final result = await api.clearExpiredImageCache();
      return result.toInt();
    } catch (e) {
      debugPrint('Failed to clear expired cache: $e');
      return 0;
    }
  }

  /// 获取缓存统计信息
  Future<api.ImageCacheStats?> getCacheStats() async {
    try {
      return await api.getImageCacheStats();
    } catch (e) {
      debugPrint('Failed to get cache stats: $e');
      return null;
    }
  }

  /// 生成缓存键（与 Rust 端保持一致，使用 MD5）
  String _generateCacheKey(String moduleId, String url) {
    final combined = '$moduleId:$url';
    final bytes = utf8.encode(combined);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// 从 URL 获取文件扩展名
  String? _getExtensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final fileName = pathSegments.last;
        final dotIndex = fileName.lastIndexOf('.');
        if (dotIndex != -1 && dotIndex < fileName.length - 1) {
          return fileName.substring(dotIndex + 1).toLowerCase();
        }
      }
    } catch (e) {
      debugPrint('Failed to get extension from URL: $e');
    }
    return null;
  }
}

