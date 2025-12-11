import 'package:flutter/material.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/screens/comic_info_screen.dart';
import 'package:comics/components/comic_card.dart';

/// 从 RemoteImageInfo 获取完整图片 URL
String getImageUrl(RemoteImageInfo info) {
  if (info.fileServer.isEmpty) return info.path;
  return '${info.fileServer}${info.path}';
}

/// 漫画列表视图（可嵌入到其他页面）
class ComicsView extends StatefulWidget {
  final String moduleId;
  final String moduleName;
  // category mode
  final String? categorySlug;
  final String? categoryTitle;
  // search mode
  final String? keyword;
  final VoidCallback? onHistoryChanged;
  final List<SortOption>? sortOptions;
  final String? sortValue;
  final ValueChanged<String>? onSortChanged;
  final bool showSortControls;

  const ComicsView({
    super.key,
    required this.moduleId,
    required this.moduleName,
    this.categorySlug,
    this.categoryTitle,
    this.keyword,
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
      final result = widget.keyword != null && widget.keyword!.isNotEmpty
          ? await searchComics(
              moduleId: widget.moduleId,
              keyword: widget.keyword!,
              sortBy: sortBy,
              page: _currentPage,
            )
          : await getComics(
              moduleId: widget.moduleId,
              categorySlug: widget.categorySlug ?? '',
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
                return ComicCard(
                  comic: _comics[index],
                  onTap: () => _openComic(_comics[index]),
                  getImageUrl: getImageUrl,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
