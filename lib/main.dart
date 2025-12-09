import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:comics/src/rust/api/init.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/api/property_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/rust/frb_generated.dart';
import 'package:comics/src/cached_image_widget.dart';
import 'package:comics/screens/comic_info_screen.dart';
import 'package:comics/src/history_manager.dart';
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

enum _HomeSection { browse, history, plugins, settings }

class _HomeScreenState extends State<HomeScreen> {
  List<ModuleInfo> _modules = [];
  ModuleInfo? _selectedModule;
  bool _loadingModules = true;
  bool _scanningModules = false;
  String? _modulesError;

  bool _loadingHistory = false;
  List<HistoryEntry> _history = [];

  _HomeSection _currentSection = _HomeSection.browse;

  @override
  void initState() {
    super.initState();
    _loadModules();
    _loadHistory();
  }

  ModuleInfo? _findModuleById(List<ModuleInfo> modules, String? id) {
    if (id == null) return null;
    try {
      return modules.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  ModuleInfo? _pickSelectedModule(List<ModuleInfo> modules, String? lastId) {
    final saved = _findModuleById(modules, lastId);
    final current = _findModuleById(modules, _selectedModule?.id);
    return saved ?? current ?? (modules.isNotEmpty ? modules.first : null);
  }

  Future<void> _loadModules({bool rescan = false}) async {
    if (!rescan) {
      setState(() {
        _loadingModules = true;
        _modulesError = null;
      });
    } else {
      setState(() {
        _scanningModules = true;
        _modulesError = null;
      });
    }

    try {
      final modules =
          rescan ? await scanAndRegisterModules() : await getModules();
      final lastId = await loadAppSetting(key: 'last_module_id');
      final selected = _pickSelectedModule(modules, lastId);

      if (mounted) {
        setState(() {
          _modules = modules;
          _selectedModule = selected;
          _loadingModules = false;
          _scanningModules = false;
        });
      }

      if (selected != null) {
        saveAppSetting(key: 'last_module_id', value: selected.id)
            .catchError((e) => debugPrint('Failed to save last module: $e'));
      }

      for (final module in modules) {
        if (!module.enabled) {
          setModuleEnabled(moduleId: module.id, enabled: true).catchError(
              (e) => debugPrint('Failed to enable module ${module.id}: $e'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _modulesError = e.toString();
          _loadingModules = false;
          _scanningModules = false;
        });
      }
    }
  }

  Future<void> _selectModule(ModuleInfo module) async {
    setState(() {
      _selectedModule = module;
    });
    setModuleEnabled(moduleId: module.id, enabled: true)
        .catchError((e) => debugPrint('Failed to enable module: $e'));
    saveAppSetting(key: 'last_module_id', value: module.id)
        .catchError((e) => debugPrint('Failed to save last module: $e'));
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final data = await HistoryManager.instance.loadHistory();
    if (!mounted) return;
    setState(() {
      _history = data;
      _loadingHistory = false;
    });
  }

  Future<void> _openHistoryEntry(HistoryEntry entry) async {
    final module = _findModuleById(_modules, entry.moduleId);
    if (module == null) {
      _showSnack('未找到对应的源，无法打开');
      return;
    }

    await _selectModule(module);
    setState(() => _currentSection = _HomeSection.browse);
    await loadModule(moduleId: module.id);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicInfoScreen(
          moduleId: module.id,
          moduleName: module.name,
          comicId: entry.comicId,
          comicTitle: entry.comicTitle,
        ),
      ),
    );
    await _loadHistory();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const ListTile(
              title: Text('选择源'),
              leading: Icon(Icons.menu_book),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loadingModules
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _modules.length,
                      itemBuilder: (context, index) {
                        final module = _modules[index];
                        final selected = _selectedModule?.id == module.id;
                        return ListTile(
                          leading: Icon(
                            Icons.extension,
                            color:
                                selected ? Theme.of(context).primaryColor : null,
                          ),
                          title: Text(module.name),
                          subtitle: Text(module.id),
                          selected: selected,
                          onTap: () {
                            Navigator.of(context).pop();
                            _selectModule(module);
                            setState(() => _currentSection = _HomeSection.browse);
                          },
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('历史记录'),
              selected: _currentSection == _HomeSection.history,
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _currentSection = _HomeSection.history);
              },
            ),
            ListTile(
              leading: const Icon(Icons.extension),
              title: const Text('插件管理'),
              selected: _currentSection == _HomeSection.plugins,
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _currentSection = _HomeSection.plugins);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              selected: _currentSection == _HomeSection.settings,
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _currentSection = _HomeSection.settings);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowseTab() {
    if (_loadingModules) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_modulesError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载模块失败: $_modulesError'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _loadModules(rescan: false),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_selectedModule == null) {
      return _buildEmptyModules();
    }

    return HomeModuleView(
      key: ValueKey(_selectedModule!.id),
      module: _selectedModule!,
      onOpenSettings: () => _openModuleSettings(_selectedModule!),
      onHistoryChanged: _loadHistory,
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_history.isEmpty) {
      return const Center(child: Text('暂无历史记录'));
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _history[index];
          return ListTile(
            leading: _buildHistoryThumb(item),
            title: Text(item.comicTitle),
            subtitle:
                Text('${item.moduleName} · ${_formatVisitedAt(item.visitedAt)}'),
            onTap: () => _openHistoryEntry(item),
          );
        },
      ),
    );
  }

  Widget _buildHistoryThumb(HistoryEntry item) {
    if (item.thumb == null) {
      return const CircleAvatar(child: Icon(Icons.book));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: CachedImageWidget(
          imageInfo: item.thumb!,
          moduleId: item.moduleId,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  String _formatVisitedAt(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildPluginTab() {
    if (_loadingModules) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _importModuleFromFile,
                icon: const Icon(Icons.file_open),
                label: const Text('导入 JS 模块'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _loadModules(rescan: true),
                icon: _scanningModules
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('重新扫描'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _modules.isEmpty
              ? _buildEmptyModules()
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _modules.length,
                  itemBuilder: (context, index) {
                    final module = _modules[index];
                    return Card(
                      child: ListTile(
                        title: Text(module.name),
                        subtitle: Text('${module.id} · v${module.version}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'settings') {
                              _openModuleSettings(module);
                            } else if (value == 'delete') {
                              _deleteModule(module);
                            } else if (value == 'use') {
                              _selectModule(module);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'use',
                              child: Text('设为当前源'),
                            ),
                            PopupMenuItem(
                              value: 'settings',
                              child: Text('设置参数'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除源'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyModules() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 80, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('暂无模块'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _loadModules(rescan: true),
            child: const Text('扫描模块'),
          ),
          TextButton(
            onPressed: _importModuleFromFile,
            child: const Text('导入 JS 文件'),
          ),
        ],
      ),
    );
  }

  Future<void> _openModuleSettings(ModuleInfo module) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModuleSettingsScreen(module: module),
      ),
    );
  }

  Future<void> _importModuleFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 JS 模块文件',
        lockParentWindow: true,
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['js'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final modulesDir = getModulesDir();
      if (modulesDir == null) {
        _showSnack('模块目录未初始化');
        return;
      }

      // 读取文件内容（优先 bytes，fallback path）
      late final List<int> rawBytes;
      late final String content;
      if (picked.bytes != null && picked.bytes!.isNotEmpty) {
        rawBytes = picked.bytes!;
        content = utf8.decode(rawBytes);
      } else if (picked.path != null) {
        final sourceFile = File(picked.path!);
        if (!await sourceFile.exists()) {
          _showSnack('文件不存在');
          return;
        }
        rawBytes = await sourceFile.readAsBytes();
        content = utf8.decode(rawBytes);
      } else {
        _showSnack('未能读取文件内容');
        return;
      }

      final moduleId = _extractModuleId(content);
      if (moduleId == null || moduleId.isEmpty) {
        _showSnack('无法识别模块 ID');
        return;
      }

      // 直接放在 modules 根目录，兼容只扫描顶层文件的实现
      final targetFile = File(p.join(modulesDir, '$moduleId.js'));
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await targetFile.writeAsBytes(rawBytes);

      await scanAndRegisterModules();
      await _loadModules(rescan: false);
      setState(() => _currentSection = _HomeSection.browse);
      _showSnack('已导入 $moduleId');
    } catch (e) {
      _showSnack('导入失败: $e');
    }
  }

  String? _extractModuleId(String content) {
    final match = RegExp(
      r"""moduleInfo\s*=\s*{[^}]*id\s*:\s*['\"]([^'\"]+)""",
      dotAll: true,
    ).firstMatch(content);
    return match?.group(1);
  }

  Future<void> _deleteModule(ModuleInfo module) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${module.name}?'),
        content: const Text('删除后将移除模块文件及相关配置，确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final modulesDir = getModulesDir();
    if (modulesDir == null) {
      _showSnack('模块目录未初始化');
      return;
    }

    try {
      // 删除根目录下的 js 文件
      final jsFile = File(p.join(modulesDir, '${module.id}.js'));
      if (await jsFile.exists()) {
        await jsFile.delete();
      }
      // 兼容旧版本：若存在子目录也清理掉
      final legacyDir = Directory(p.join(modulesDir, module.id));
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
      }

      await clearModuleProperties(moduleId: module.id);
      await ImageCacheManager().clearCacheByModule(module.id);
      await HistoryManager.instance.removeByModule(module.id);

      await scanAndRegisterModules();
      await _loadModules(rescan: false);
      await _loadHistory();

      // 在 _loadModules 完成后，检查是否需要更新选中的模块
      // 因为 _loadModules 已经更新了 _selectedModule，这里只需要确保 UI 刷新
      if (!mounted) return;
      
      // 如果删除的是当前选中的模块，且列表不为空，确保选中第一个
      if (_modules.isNotEmpty && (_selectedModule == null || _selectedModule!.id == module.id)) {
        setState(() {
          _selectedModule = _modules.first;
        });
      }

      _showSnack('已删除 ${module.name}');
    } catch (e) {
      _showSnack('删除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_currentSection) {
      case _HomeSection.browse:
        body = _buildBrowseTab();
        break;
      case _HomeSection.history:
        body = _buildHistoryTab();
        break;
      case _HomeSection.plugins:
        body = _buildPluginTab();
        break;
      case _HomeSection.settings:
        body = const SettingsScreen();
        break;
    }

    final isBrowse = _currentSection == _HomeSection.browse;
    final title = isBrowse
        ? (_selectedModule?.name ?? 'Comics Browser')
        : _currentSection == _HomeSection.history
            ? '历史记录'
            : _currentSection == _HomeSection.plugins
                ? '插件管理'
                : '设置';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              if (isBrowse && _selectedModule != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ModuleSettingsScreen(module: _selectedModule!),
                  ),
                );
              } else {
                setState(() => _currentSection = _HomeSection.settings);
              }
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: body,
    );
  }
}

/// 嵌入式模块浏览视图（带分类选择）
class HomeModuleView extends StatefulWidget {
  final ModuleInfo module;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onHistoryChanged;

  const HomeModuleView({
    super.key,
    required this.module,
    this.onOpenSettings,
    this.onHistoryChanged,
  });

  @override
  State<HomeModuleView> createState() => _HomeModuleViewState();
}

class _HomeModuleViewState extends State<HomeModuleView> {
  List<Category> _categories = [];
  Category? _selectedCategory;
  bool _loading = true;
  String? _error;
  List<SortOption> _sortOptions = [];
  String _currentSort = '';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didUpdateWidget(covariant HomeModuleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module.id != widget.module.id) {
      _categories = [];
      _selectedCategory = null;
      _error = null;
      _loading = true;
      _sortOptions = [];
      _currentSort = '';
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      await loadModule(moduleId: widget.module.id);
      final categories = await getCategories(moduleId: widget.module.id);
      final sorts = await getSortOptions(moduleId: widget.module.id);

      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (categories.isNotEmpty) {
          _selectedCategory = categories.first;
        }
        _sortOptions = sorts;
        _currentSort = sorts.isNotEmpty ? sorts.first.value : '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (_categories.isNotEmpty)
                TextButton.icon(
                  onPressed: _showCategoryPicker,
                  icon: const Icon(Icons.category, size: 20),
                  label: Text(
                    _selectedCategory?.title ?? '选择分类',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              const SizedBox(width: 8),
              if (_sortOptions.isNotEmpty)
                DropdownButton<String>(
                  value: _currentSort.isNotEmpty ? _currentSort : null,
                  hint: const Text('选择排序'),
                  items: _sortOptions
                      .map((s) => DropdownMenuItem<String>(
                            value: s.value,
                            child: Text(s.name),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _currentSort = value);
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
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
              onPressed: _loadCategories,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_categories.isEmpty) {
      return const Center(child: Text('暂无分类'));
    }

    if (_selectedCategory != null) {
      return ComicsView(
        key: ValueKey('${widget.module.id}_${_selectedCategory!.id}'),
        moduleId: widget.module.id,
        moduleName: widget.module.name,
        categorySlug: _selectedCategory!.id,
        categoryTitle: _selectedCategory!.title,
        onHistoryChanged: widget.onHistoryChanged,
        sortOptions: _sortOptions,
        sortValue: _currentSort,
        onSortChanged: (value) {
          setState(() => _currentSort = value);
        },
        showSortControls: false,
      );
    }

    return const Center(child: Text('请选择分类'));
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
  final VoidCallback? onHistoryChanged;
  final List<SortOption>? sortOptions;
  final String? sortValue;
  final ValueChanged<String>? onSortChanged;
  final bool showSortControls;

  const ComicsView({
    super.key,
    required this.moduleId,
    required this.moduleName,
    required this.categorySlug,
    required this.categoryTitle,
    this.onHistoryChanged,
    this.sortOptions,
    this.sortValue,
    this.onSortChanged,
    this.showSortControls = true,
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
    if (widget.sortOptions != null) {
      _sortOptions = widget.sortOptions!;
      _currentSort = widget.sortValue ??
          (widget.sortOptions!.isNotEmpty ? widget.sortOptions!.first.value : '');
      _loadComics();
    } else {
      _loadSortOptions();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ComicsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sortOptions != null &&
        (oldWidget.sortOptions != widget.sortOptions ||
            oldWidget.sortValue != widget.sortValue)) {
      _sortOptions = widget.sortOptions ?? _sortOptions;
      _currentSort = widget.sortValue ??
          (widget.sortOptions != null && widget.sortOptions!.isNotEmpty
              ? widget.sortOptions!.first.value
              : _currentSort);
      _loadComics(refresh: true);
    }
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
      final sortBy = widget.sortValue ?? _currentSort;
      final result = await getComics(
        moduleId: widget.moduleId,
        categorySlug: widget.categorySlug,
        sortBy: sortBy,
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
    if (widget.onSortChanged != null) {
      widget.onSortChanged!(sortId);
    } else {
      setState(() {
        _currentSort = sortId;
      });
      _loadComics(refresh: true);
    }
  }

  Future<void> _openComic(ComicSimple comic) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicInfoScreen(
          moduleId: widget.moduleId,
          moduleName: widget.moduleName,
          comicId: comic.id,
          comicTitle: comic.title,
        ),
      ),
    );
    widget.onHistoryChanged?.call();
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
        if (widget.showSortControls && _sortOptions.isNotEmpty)
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
                        final isSelected = (_currentSort == option.value) ||
                            (widget.sortValue != null && widget.sortValue == option.value);
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
              ],
            ),
          ),
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
