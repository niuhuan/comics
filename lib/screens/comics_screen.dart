import 'package:flutter/material.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/cached_image_widget.dart';
import 'comic_info_screen.dart';

/// 从 RemoteImageInfo 获取完整图片 URL
String getImageUrl(RemoteImageInfo info) {
  if (info.fileServer.isEmpty) return info.path;
  return '${info.fileServer}${info.path}';
}

/// 漫画列表页面
class ComicsScreen extends StatefulWidget {
  final String moduleId;
  final String moduleName;
  final String categorySlug;
  final String categoryTitle;

  const ComicsScreen({
    super.key,
    required this.moduleId,
    required this.moduleName,
    required this.categorySlug,
    required this.categoryTitle,
  });

  @override
  State<ComicsScreen> createState() => _ComicsScreenState();
}

class _ComicsScreenState extends State<ComicsScreen> {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryTitle),
        actions: [
          if (_sortOptions.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              onSelected: _changeSort,
              itemBuilder: (context) => _sortOptions.map((option) {
                return PopupMenuItem<String>(
                  value: option.value,
                  child: Row(
                    children: [
                      if (_currentSort == option.value)
                        const Icon(Icons.check, size: 18)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Text(option.name),
                    ],
                  ),
                );
              }).toList(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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

    return RefreshIndicator(
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
            moduleId: widget.moduleId,
            onTap: () => _openComic(_comics[index]),
          );
        },
      ),
    );
  }
}

/// 漫画卡片
class _ComicCard extends StatelessWidget {
  final ComicSimple comic;
  final String moduleId;
  final VoidCallback onTap;

  const _ComicCard({
    required this.comic,
    required this.moduleId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                  CachedImageWidget(
                    imageInfo: comic.thumb,
                    moduleId: moduleId,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, size: 40),
                    ),
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
