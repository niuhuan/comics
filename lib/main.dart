import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:comics/src/rust/api/init.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/rust/frb_generated.dart';
import 'package:comics/screens/comic_info_screen.dart';
import 'package:comics/src/image_cache_manager.dart';
import 'package:comics/src/rust/api/image_cache_api.dart' as api;

/// 从 RemoteImageInfo 获取完整图片 URL
String getImageUrl(RemoteImageInfo info) {
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
  Category? _selectedCategory;
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
      
      debugPrint('[ModuleScreen] Loading module: ${widget.module.id}');
      
      // 加载模块
      await loadModule(moduleId: widget.module.id);
      
      debugPrint('[ModuleScreen] Module loaded, getting categories...');
      
      // 获取分类
      final categories = await getCategories(moduleId: widget.module.id);
      
      debugPrint('[ModuleScreen] Got ${categories.length} categories');
      
      setState(() {
        _categories = categories;
        // 默认选中第一个分类
        if (categories.isNotEmpty) {
          _selectedCategory = categories.first;
        }
        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('[ModuleScreen] Error: $e');
      debugPrint('[ModuleScreen] StackTrace: $stackTrace');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('选择分类', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory?.id == cat.id;
                  return ListTile(
                    leading: isSelected 
                        ? const Icon(Icons.check, color: Colors.deepPurple)
                        : const SizedBox(width: 24),
                    title: Text(cat.title),
                    selected: isSelected,
                    onTap: () {
                      setState(() => _selectedCategory = cat);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModuleSettingsScreen(module: widget.module),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.module.name),
        actions: [
          // 分类选择器
          if (_categories.isNotEmpty)
            TextButton.icon(
              onPressed: _showCategoryPicker,
              icon: const Icon(Icons.category, size: 20),
              label: Text(
                _selectedCategory?.title ?? '选择分类',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '模块设置',
            onPressed: _openSettings,
          ),
        ],
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

    // 直接显示当前选中分类的漫画列表
    if (_selectedCategory != null) {
      return ComicsView(
        key: ValueKey(_selectedCategory!.id),
        moduleId: widget.module.id,
        moduleName: widget.module.name,
        categorySlug: _selectedCategory!.id,
        categoryTitle: _selectedCategory!.title,
      );
    }
    
    return const Center(child: Text('请选择分类'));
  }
}

/// 图片缓存设置项
class _ImageCacheSettingsTile extends StatefulWidget {
  const _ImageCacheSettingsTile();

  @override
  State<_ImageCacheSettingsTile> createState() => _ImageCacheSettingsTileState();
}

class _ImageCacheSettingsTileState extends State<_ImageCacheSettingsTile> {
  final _cacheManager = ImageCacheManager();
  api.ImageCacheStats? _stats;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final stats = await _cacheManager.getCacheStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _clearExpiredCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除过期缓存'),
        content: const Text('确定要清除所有过期的图片缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final count = await _cacheManager.clearExpiredCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 $count 个过期缓存')),
        );
        await _loadStats();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有缓存'),
        content: const Text('确定要清除所有图片缓存吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final count = await _cacheManager.clearAllCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 $count 个缓存')),
        );
        await _loadStats();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.image),
      title: const Text('图片缓存'),
      subtitle: _loading
          ? const Text('加载中...')
          : _stats != null
              ? Text('${_stats!.validCount} 个有效缓存，${_formatBytes(_stats!.totalSize.toInt())}')
              : const Text('点击查看详情'),
      children: [
        if (_stats != null) ...[
          ListTile(
            dense: true,
            title: const Text('缓存统计'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('总数量: ${_stats!.totalCount}'),
                Text('有效: ${_stats!.validCount}'),
                Text('已过期: ${_stats!.expiredCount}'),
                Text('总大小: ${_formatBytes(_stats!.totalSize.toInt())}'),
              ],
            ),
          ),
        ],
        ListTile(
          dense: true,
          leading: const Icon(Icons.delete_outline),
          title: const Text('清除过期缓存'),
          subtitle: const Text('删除所有已过期的图片缓存'),
          onTap: _clearExpiredCache,
          enabled: !_loading,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.delete_forever),
          title: const Text('清除所有缓存'),
          subtitle: const Text('删除所有图片缓存'),
          onTap: _clearAllCache,
          enabled: !_loading,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.refresh),
          title: const Text('刷新统计'),
          onTap: _loadStats,
          enabled: !_loading,
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
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
          // 图片缓存管理
          _ImageCacheSettingsTile(),
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

/// 漫画列表视图（可嵌入到其他页面）
class ComicsView extends StatefulWidget {
  final String moduleId;
  final String moduleName;
  final String categorySlug;
  final String categoryTitle;

  const ComicsView({
    super.key,
    required this.moduleId,
    required this.moduleName,
    required this.categorySlug,
    required this.categoryTitle,
  });

  @override
  State<ComicsView> createState() => _ComicsViewState();
}

class _ComicsViewState extends State<ComicsView> {
  final List<ComicSimple> _comics = [];
  final ScrollController _scrollController = ScrollController();
  
  List<SortOption> _sortOptions = [];
  String _currentSort = '';
  int _currentPage = 1;
  int _totalPages = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSortOptions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadSortOptions() async {
    try {
      final options = await getSortOptions(moduleId: widget.moduleId);
      setState(() {
        _sortOptions = options;
        _currentSort = options.isNotEmpty ? options.first.value : '';
      });
      _loadComics();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _loadComics({bool refresh = false}) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
      if (refresh) {
        _comics.clear();
        _currentPage = 1;
        _hasMore = true;
      }
    });

    try {
      final result = await getComics(
        moduleId: widget.moduleId,
        categorySlug: widget.categorySlug,
        sortBy: _currentSort,
        page: _currentPage,
      );

      setState(() {
        _comics.addAll(result.docs);
        _totalPages = result.pageInfo.pages;
        _hasMore = _currentPage < _totalPages;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _currentPage++;
    await _loadComics();
  }

  Future<void> _refresh() async {
    await _loadComics(refresh: true);
  }

  void _changeSort(String sortId) {
    if (_currentSort == sortId) return;
    setState(() {
      _currentSort = sortId;
    });
    _loadComics(refresh: true);
  }

  void _openComic(ComicSimple comic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicInfoScreen(
          moduleId: widget.moduleId,
          moduleName: widget.moduleName,
          comicId: comic.id,
          comicTitle: comic.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _comics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text('加载失败', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refresh,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_comics.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_comics.isEmpty) {
      return const Center(child: Text('暂无漫画'));
    }

    return Column(
      children: [
        // 排序和刷新按钮
        if (_sortOptions.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text('排序:', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _sortOptions.map((option) {
                        final isSelected = _currentSort == option.value;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(option.name),
                            selected: isSelected,
                            onSelected: (_) => _changeSort(option.value),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                  tooltip: '刷新',
                ),
              ],
            ),
          ),
        // 漫画列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _comics.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _comics.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                return _ComicCard(
                  comic: _comics[index],
                  onTap: () => _openComic(_comics[index]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 漫画卡片
class _ComicCard extends StatelessWidget {
  final ComicSimple comic;
  final VoidCallback onTap;

  const _ComicCard({
    required this.comic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final thumbUrl = getImageUrl(comic.thumb);
    
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, size: 40),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                  // 完结标识
                  if (comic.finished)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '完结',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  // 章节数
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${comic.epsCount}话',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (comic.author.isNotEmpty)
                    Text(
                      comic.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 模块设置页面
class ModuleSettingsScreen extends StatefulWidget {
  final ModuleInfo module;
  
  const ModuleSettingsScreen({super.key, required this.module});

  @override
  State<ModuleSettingsScreen> createState() => _ModuleSettingsScreenState();
}

class _ModuleSettingsScreenState extends State<ModuleSettingsScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _message;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final username = await getModuleStorage(
        moduleId: widget.module.id,
        key: 'username',
      );
      final password = await getModuleStorage(
        moduleId: widget.module.id,
        key: 'password',
      );
      
      if (username != null) {
        _usernameController.text = username;
      }
      if (password != null) {
        _passwordController.text = password;
      }
    } catch (e) {
      debugPrint('Failed to load credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    if (_loading) return;
    
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      // 保存账号密码
      await setModuleStorage(
        moduleId: widget.module.id,
        key: 'username',
        value: _usernameController.text,
      );
      await setModuleStorage(
        moduleId: widget.module.id,
        key: 'password',
        value: _passwordController.text,
      );
      
      setState(() {
        _message = '保存成功';
        _isSuccess = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _message = '保存失败: $e';
        _isSuccess = false;
        _loading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    // 检查是否需要账号设置（pikapika 和 jasmine）
    final needsLogin = widget.module.id == 'pikapika' || 
                       widget.module.id == 'jasmine';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.module.name} 设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 模块信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.extension, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.module.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'ID: ${widget.module.id}',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 账号设置（仅 pikapika 和 jasmine）
          if (needsLogin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_circle),
                        SizedBox(width: 8),
                        Text(
                          '账号设置',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '账号/邮箱',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword 
                                ? Icons.visibility_off 
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 16),
                    
                    // 提示消息
                    if (_message != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _isSuccess 
                              ? Colors.green[50] 
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isSuccess 
                                ? Colors.green 
                                : Colors.red,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isSuccess 
                                  ? Icons.check_circle 
                                  : Icons.error,
                              color: _isSuccess 
                                  ? Colors.green 
                                  : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_message!)),
                          ],
                        ),
                      ),
                    
                    // 按钮
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _saveCredentials,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      '此模块无需配置',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
