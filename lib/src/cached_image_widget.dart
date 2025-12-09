import 'dart:io';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:comics/src/image_cache_manager.dart';
import 'package:comics/src/rust/modules/types.dart';

/// 带缓存的图片组件
class CachedImageWidget extends StatefulWidget {
  final RemoteImageInfo imageInfo;
  final String moduleId;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;

  const CachedImageWidget({
    super.key,
    required this.imageInfo,
    required this.moduleId,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  @override
  State<CachedImageWidget> createState() => _CachedImageWidgetState();
}

class _CachedImageWidgetState extends State<CachedImageWidget> {
  final _cacheManager = ImageCacheManager();
  String? _cachedPath;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final imageUrl = _getImageUrl();
      
      // 先尝试从缓存获取
      final cachedPath = await _cacheManager.getCachedImagePath(
        widget.moduleId,
        imageUrl,
      );
      
      if (cachedPath != null && await File(cachedPath).exists()) {
        if (mounted) {
          setState(() {
            _cachedPath = cachedPath;
            _loading = false;
          });
        }
        return;
      }

      // 缓存不存在，下载并缓存
      // 提取图片处理参数（从 URL 中）
      final processParams = _extractProcessParams(widget.moduleId, imageUrl);
      
      final newCachedPath = await _cacheManager.cacheImage(
        widget.moduleId,
        imageUrl,
        headers: widget.imageInfo.headers,
        processParams: processParams,
      );

      if (mounted) {
        setState(() {
          _cachedPath = newCachedPath;
          _loading = false;
          if (newCachedPath == null) {
            _error = 'Failed to load image';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _getImageUrl() {
    if (widget.imageInfo.fileServer.isEmpty) {
      return widget.imageInfo.path;
    }
    return '${widget.imageInfo.fileServer}${widget.imageInfo.path}';
  }

  /// 从 URL 中提取图片处理参数
  /// 不同模块可能需要不同的参数
  Map<String, dynamic>? _extractProcessParams(String moduleId, String url) {
    // jasmine 模块：URL 格式为 https://${cdnHost}/media/photos/${chapterId}/${imageName}?v=
    if (moduleId == 'jasmine') {
      try {
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        // 查找 'photos' 的位置
        final photosIndex = pathSegments.indexOf('photos');
        if (photosIndex != -1 && photosIndex + 2 < pathSegments.length) {
          final chapterId = pathSegments[photosIndex + 1];
          final imageName = pathSegments[photosIndex + 2];
          return {
            'chapterId': chapterId,
            'imageName': imageName,
          };
        }
      } catch (e) {
        debugPrint('Failed to extract process params from URL: $e');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
    }

    if (_error != null || _cachedPath == null) {
      return widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image),
          );
    }

    // 使用 ExtendedImage 加载本地缓存文件
    return ExtendedImage.file(
      File(_cachedPath!),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return widget.placeholder ??
                Container(
                  width: widget.width,
                  height: widget.height,
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
          case LoadState.completed:
            return null; // 显示图片
          case LoadState.failed:
            return widget.errorWidget ??
                Container(
                  width: widget.width,
                  height: widget.height,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image),
                );
        }
      },
    );
  }
}

/// 网络图片组件（使用自定义缓存）
class CachedNetworkImageWidget extends StatelessWidget {
  final String url;
  final String moduleId;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;
  final Map<String, String>? headers;

  const CachedNetworkImageWidget({
    super.key,
    required this.url,
    required this.moduleId,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.headers,
  });

  @override
  Widget build(BuildContext context) {
    return _CachedNetworkImageWidgetStateful(
      url: url,
      moduleId: moduleId,
      fit: fit,
      placeholder: placeholder,
      errorWidget: errorWidget,
      width: width,
      height: height,
      headers: headers,
    );
  }
}

class _CachedNetworkImageWidgetStateful extends StatefulWidget {
  final String url;
  final String moduleId;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;
  final Map<String, String>? headers;

  const _CachedNetworkImageWidgetStateful({
    required this.url,
    required this.moduleId,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.headers,
  });

  @override
  State<_CachedNetworkImageWidgetStateful> createState() =>
      _CachedNetworkImageWidgetStatefulState();
}

class _CachedNetworkImageWidgetStatefulState
    extends State<_CachedNetworkImageWidgetStateful> {
  final _cacheManager = ImageCacheManager();
  String? _cachedPath;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      // 先尝试从缓存获取
      final cachedPath = await _cacheManager.getCachedImagePath(
        widget.moduleId,
        widget.url,
      );

      if (cachedPath != null && await File(cachedPath).exists()) {
        if (mounted) {
          setState(() {
            _cachedPath = cachedPath;
            _loading = false;
          });
        }
        return;
      }

      // 缓存不存在，下载并缓存
      final newCachedPath = await _cacheManager.cacheImage(
        widget.moduleId,
        widget.url,
        headers: widget.headers,
      );

      if (mounted) {
        setState(() {
          _cachedPath = newCachedPath;
          _loading = false;
          if (newCachedPath == null) {
            _error = 'Failed to load image';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
    }

    if (_error != null || _cachedPath == null) {
      return widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image),
          );
    }

    // 使用 ExtendedImage 加载本地缓存文件
    return ExtendedImage.file(
      File(_cachedPath!),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return widget.placeholder ??
                Container(
                  width: widget.width,
                  height: widget.height,
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
          case LoadState.completed:
            return null; // 显示图片
          case LoadState.failed:
            return widget.errorWidget ??
                Container(
                  width: widget.width,
                  height: widget.height,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image),
                );
        }
      },
    );
  }
}

