import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:comics/src/rust/api/init.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/rust/frb_generated.dart';

/// 从 RemoteImageInfo 获取完整图片 URL
String? getImageUrl(RemoteImageInfo? info) {
  if (info == null) return null;
  if (info.fileServer.isEmpty) return info.path;
  return '${info.fileServer}${info.path}';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comics Browser',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const InitScreen(),
    );
  }
}

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
            const Icon(Icons.menu_book, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 20),
            const Text(
              'Comics Browser',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            if (!_initialized && _error == null)
              const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_status),
            if (_error != null) ...[
              const SizedBox(height: 20),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _status = '正在重试...';
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

/// 主页面
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ModuleInfo> _modules = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModules();
  }

  Future<void> _loadModules() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      
      final modules = await getModules();
      
      setState(() {
        _modules = modules;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comics Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadModules,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddModuleDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('错误: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadModules,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    
    if (_modules.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            const Text('暂无模块', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 10),
            const Text(
              '请将 .js 模块文件放入 modules 目录',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final modules = await scanAndRegisterModules();
                setState(() => _modules = modules);
              },
              child: const Text('扫描模块'),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _modules.length,
      itemBuilder: (context, index) {
        final module = _modules[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: module.enabled ? Colors.green : Colors.grey,
            child: Text(module.name[0].toUpperCase()),
          ),
          title: Text(module.name),
          subtitle: Text('${module.id} - v${module.version}'),
          trailing: Switch(
            value: module.enabled,
            onChanged: (enabled) async {
              await setModuleEnabled(moduleId: module.id, enabled: enabled);
              _loadModules();
            },
          ),
          onTap: module.enabled ? () => _openModule(module) : null,
        );
      },
    );
  }

  void _openModule(ModuleInfo module) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModuleScreen(module: module),
      ),
    );
  }

  void _showAddModuleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加模块'),
        content: const Text(
          '将 .js 模块文件放入 modules 目录，然后点击扫描。\n\n'
          '模块目录路径可在设置中查看。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final modules = await scanAndRegisterModules();
              setState(() => _modules = modules);
            },
            child: const Text('扫描模块'),
          ),
        ],
      ),
    );
  }
}

/// 模块页面
class ModuleScreen extends StatefulWidget {
  final ModuleInfo module;
  
  const ModuleScreen({super.key, required this.module});

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  List<Category> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      
      // 加载模块
      await loadModule(moduleId: widget.module.id);
      
      // 获取分类
      final categories = await getCategories(moduleId: widget.module.id);
      
      setState(() {
        _categories = categories;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.name),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 20),
              Text(
                '加载失败',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loadCategories,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_categories.isEmpty) {
      return const Center(
        child: Text('暂无分类'),
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        return Card(
          child: InkWell(
            onTap: () => _openCategory(category),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (category.thumb != null)
                  Expanded(
                    child: Image.network(
                      getImageUrl(category.thumb)!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 40),
                    ),
                  )
                else
                  const Icon(Icons.folder, size: 40),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    category.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openCategory(Category category) {
    // TODO: 打开分类漫画列表页面
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('打开分类: ${category.title}')),
    );
  }
}

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('应用目录'),
            subtitle: FutureBuilder<String?>(
              future: Future.value(getRootPath()),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? '未初始化');
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('模块目录'),
            subtitle: FutureBuilder<String?>(
              future: Future.value(getModulesDir()),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? '未初始化');
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('缓存目录'),
            subtitle: FutureBuilder<String?>(
              future: Future.value(getCacheDir()),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? '未初始化');
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            subtitle: const Text('Comics Browser v1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Comics Browser',
                applicationVersion: '1.0.0',
                applicationLegalese: '基于 Flutter + Rust 架构的多模块漫画浏览器',
              );
            },
          ),
        ],
      ),
    );
  }
}
