import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/components/comics_view.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/api/property_api.dart';

class SearchScreen extends StatefulWidget {
  final ModuleInfo module;
  final String? initialKeyword;

  const SearchScreen({super.key, required this.module, this.initialKeyword});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialKeyword ?? '');
  String _keyword = '';
  List<SortOption> _sortOptions = [];
  String _currentSort = '';
  bool _loadingSorts = true;
  String? _error;
  Timer? _debounce;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _keyword = widget.initialKeyword ?? '';
    _loadSorts();
    _loadHistory();
  }

  Future<void> _loadSorts() async {
    setState(() {
      _loadingSorts = true;
      _error = null;
    });
    try {
      final sorts = await getSortOptions(moduleId: widget.module.id);
      if (!mounted) return;
      setState(() {
        _sortOptions = sorts;
        _currentSort = sorts.isNotEmpty ? sorts.first.value : '';
        _loadingSorts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingSorts = false;
      });
    }
  }

  void _submitSearch() {
    setState(() {
      _keyword = _controller.text.trim();
    });
    _saveKeywordToHistory(_keyword);
  }

  // 改为仅在提交时搜索，不在输入变化时自动搜索

  Future<void> _loadHistory() async {
    try {
      final jsonStr = await loadProperty(
        moduleId: widget.module.id,
        key: 'search_history',
      );
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = List<String>.from(json.decode(jsonStr));
        if (!mounted) return;
        setState(() {
          _history = list;
        });
      }
    } catch (e) {
      // ignore parsing/storage errors
    }
  }

  Future<void> _saveKeywordToHistory(String kw) async {
    final v = kw.trim();
    if (v.isEmpty) return;
    // de-dup and cap length
    _history.removeWhere((e) => e == v);
    _history.insert(0, v);
    if (_history.length > 10) {
      _history = _history.sublist(0, 10);
    }
    try {
      await saveProperty(
        moduleId: widget.module.id,
        key: 'search_history',
        value: json.encode(_history),
      );
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _deleteHistoryItem(String kw) async {
    _history.removeWhere((e) => e == kw);
    try {
      await saveProperty(
        moduleId: widget.module.id,
        key: 'search_history',
        value: json.encode(_history),
      );
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: '搜索',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          // 仅提交时触发搜索
          onSubmitted: (_) => _submitSearch(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _submitSearch,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingSorts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadSorts, child: const Text('重试')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_history.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _history.map((kw) {
                return InputChip(
                  label: Text(kw),
                  onPressed: () {
                    _controller.text = kw;
                    _submitSearch();
                  },
                  onDeleted: () => _deleteHistoryItem(kw),
                );
              }).toList(),
            ),
          ),
        Expanded(
          child: _keyword.isEmpty
              ? const Center(child: Text('请输入关键字进行搜索'))
              : ComicsView(
                  key: ValueKey('search_${widget.module.id}_$_keyword'),
                  moduleId: widget.module.id,
                  moduleName: widget.module.name,
                  keyword: _keyword,
                  sortOptions: _sortOptions,
                  sortValue: _currentSort,
                  onSortChanged: (v) => setState(() => _currentSort = v),
                  showSortControls: true,
                ),
        ),
      ],
    );
  }
}
