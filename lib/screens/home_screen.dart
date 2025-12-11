import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:comics/src/rust/api/init.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/api/property_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/cached_image_widget.dart';
import 'package:comics/screens/comic_info_screen.dart';
import 'package:comics/screens/module_settings_screen.dart';
import 'package:comics/screens/settings_screen.dart';
import 'package:comics/components/home_module_view.dart';
import 'package:comics/screens/search_screen.dart';
import 'package:comics/src/history_manager.dart';
import 'package:comics/src/image_cache_manager.dart';

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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
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
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _importModuleFromFile,
                icon: const Icon(Icons.file_open),
                label: const Text('从文件导入'),
              ),
              ElevatedButton.icon(
                onPressed: _importModuleFromUrl,
                icon: const Icon(Icons.link),
                label: const Text('从URL导入'),
              ),
              OutlinedButton.icon(
                onPressed: _updateAllModules,
                icon: const Icon(Icons.system_update),
                label: const Text('更新所有(有来源)'),
              ),
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
                    final hasSourceUrl = module.sourceUrl != null && module.sourceUrl!.isNotEmpty;
                    
                    return Card(
                      child: ListTile(
                        title: Text(module.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${module.id} · v${module.version}'),
                            if (hasSourceUrl)
                              Text(
                                '来源: ${module.sourceUrl}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'settings') {
                              _openModuleSettings(module);
                            } else if (value == 'delete') {
                              _deleteModule(module);
                            } else if (value == 'use') {
                              _selectModule(module);
                            } else if (value == 'update') {
                              _updateModule(module);
                            } else if (value == 'edit_source') {
                              _editModuleSource(module);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'use',
                              child: Text('设为当前源'),
                            ),
                            const PopupMenuItem(
                              value: 'settings',
                              child: Text('设置参数'),
                            ),
                            const PopupMenuItem(
                              value: 'edit_source',
                              child: Text('编辑来源URL'),
                            ),
                            PopupMenuItem(
                              value: 'update',
                              enabled: hasSourceUrl,
                              child: Row(
                                children: [
                                  Text(
                                    '更新插件',
                                    style: TextStyle(
                                      color: hasSourceUrl ? null : Colors.grey,
                                    ),
                                  ),
                                  if (!hasSourceUrl) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.grey[400],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const PopupMenuItem(
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

  Future<void> _editModuleSource(ModuleInfo module) async {
    final controller = TextEditingController(text: module.sourceUrl ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑来源 - ${module.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/plugin.js (留空清除)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('清除')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    try {
      await setModuleSourceUrl(moduleId: module.id, sourceUrl: result.isEmpty ? null : result);
      await _loadModules(rescan: false);
      _showSnack(result.isEmpty ? '已清除来源' : '来源已更新');
    } catch (e) {
      _showSnack('保存失败: $e');
    }
  }

  Future<void> _updateAllModules() async {
    final candidates = _modules.where((m) => (m.sourceUrl ?? '').isNotEmpty).toList();
    if (candidates.isEmpty) {
      _showSnack('没有可更新的插件');
      return;
    }
    _showSnack('开始更新 ${candidates.length} 个插件');
    for (final m in candidates) {
      try {
        await updateModule(moduleId: m.id);
      } catch (e) {
        debugPrint('更新失败 ${m.id}: $e');
      }
    }
    await _loadModules(rescan: false);
    _showSnack('更新完成');
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

      final targetFile = File(p.join(modulesDir, '$moduleId.js'));
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await targetFile.writeAsBytes(rawBytes);

      await registerModule(moduleId: moduleId);
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

  Future<void> _importModuleFromUrl() async {
    final controller = TextEditingController();
    
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 URL 导入插件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入插件的 URL 地址：'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'https://example.com/plugin.js',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty) return;

    try {
      _showSnack('正在下载插件...');
      await importModuleFromUrl(url: url);
      await _loadModules(rescan: false);
      setState(() => _currentSection = _HomeSection.browse);
      _showSnack('插件导入成功');
    } catch (e) {
      _showSnack('导入失败: $e');
    }
  }

  Future<void> _updateModule(ModuleInfo module) async {
    // UI层已经确保只有有source_url的插件才能触发更新
    try {
      _showSnack('正在更新插件...');
      await updateModule(moduleId: module.id);
      await _loadModules(rescan: false);
      _showSnack('插件更新成功');
    } catch (e) {
      _showSnack('更新失败: $e');
    }
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

    try {
      // 清除模块数据
      await clearModuleProperties(moduleId: module.id);
      await ImageCacheManager().clearCacheByModule(module.id);
      await HistoryManager.instance.removeByModule(module.id);
      
      // 使用新的删除API
      await deleteModule(moduleId: module.id);
      
      await _loadModules(rescan: false);
      await _loadHistory();

      if (!mounted) return;
      
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
          if (isBrowse && _selectedModule != null)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(module: _selectedModule!),
                  ),
                );
              },
            ),
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
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
