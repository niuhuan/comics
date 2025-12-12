import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:comics/src/rust/api/init.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/image_cache_manager.dart';
import 'package:comics/screens/home_screen.dart';

/// 初始化屏幕
class InitScreen extends StatefulWidget {
  const InitScreen({super.key});

  @override
  State<InitScreen> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  String _status = '正在初始化...';
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // 检查是否已经初始化
      if (isInitialized()) {
        // 如果已经初始化，直接跳转到主页面
        setState(() {
          _status = '应用已就绪';
          _initialized = true;
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
        return;
      }

      // 获取应用数据目录
      final directory = await _getAppDirectory();
      setState(() => _status = '初始化应用目录: $directory');
      
      // 初始化 Rust 端
      await initApplication(rootPath: directory);
      
      setState(() => _status = '扫描模块...');
      
      // 扫描并注册模块
      final modules = await scanAndRegisterModules();
      
      setState(() {
        _status = '初始化完成，发现 ${modules.length} 个模块';
        _initialized = true;
      });
      
      // 清除过期的图片缓存（后台执行，不阻塞）
      ImageCacheManager().clearExpiredCache().catchError((e) {
        debugPrint('Failed to clear expired cache: $e');
        return 0;
      });
      
      // 延迟跳转到主页面
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _status = '初始化失败';
      });
    }
  }

  Future<String> _getAppDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } else if (Platform.isMacOS || Platform.isLinux) {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    } else if (Platform.isWindows) {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/Comics';
    }
    throw UnsupportedError('Unsupported platform');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_error == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _status,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                _status,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _status = '正在初始化...';
                  });
                  _initialize();
                },
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
