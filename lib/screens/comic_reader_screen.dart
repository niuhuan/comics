import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'comics_screen.dart';

/// 漫画阅读器页面
class ComicReaderScreen extends StatefulWidget {
  final String moduleId;
  final String comicId;
  final String comicTitle;
  final List<Ep> epList;
  final Ep currentEp;
  final int? initPosition;

  const ComicReaderScreen({
    super.key,
    required this.moduleId,
    required this.comicId,
    required this.comicTitle,
    required this.epList,
    required this.currentEp,
    this.initPosition,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  List<Picture> _pictures = [];
  bool _loading = true;
  String? _error;
  bool _fullScreen = false;
  int _currentIndex = 0;
  late Ep _currentEp;
  
  final PageController _pageController = PageController();
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentEp = widget.currentEp;
    _loadPictures();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformController.dispose();
    // 退出时恢复系统 UI
    if (_fullScreen) {
      _exitFullScreen();
    }
    super.dispose();
  }

  Future<void> _loadPictures() async {
    setState(() {
      _loading = true;
      _error = null;
      _pictures = [];
    });

    try {
      List<Picture> allPictures = [];
      int page = 1;
      int totalPages = 1;

      do {
        final picturePage = await getPictures(
          moduleId: widget.moduleId,
          comicId: widget.comicId,
          epId: _currentEp.id,
          page: page,
        );
        allPictures.addAll(picturePage.docs);
        totalPages = picturePage.pageInfo.pages;
        page++;
      } while (page <= totalPages);

      setState(() {
        _pictures = allPictures;
        _loading = false;
        _currentIndex = widget.initPosition ?? 0;
      });

      // 跳转到指定位置
      if (widget.initPosition != null && widget.initPosition! > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(widget.initPosition!);
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _fullScreen = !_fullScreen;
      if (_fullScreen) {
        _enterFullScreen();
      } else {
        _exitFullScreen();
      }
    });
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  void _goToPreviousEp() {
    final currentOrder = _currentEp.order;
    final previousEp = widget.epList.where((e) => e.order < currentOrder).toList();
    if (previousEp.isNotEmpty) {
      previousEp.sort((a, b) => b.order.compareTo(a.order));
      _changeEp(previousEp.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已经是第一章了')),
      );
    }
  }

  void _goToNextEp() {
    final currentOrder = _currentEp.order;
    final nextEp = widget.epList.where((e) => e.order > currentOrder).toList();
    if (nextEp.isNotEmpty) {
      nextEp.sort((a, b) => a.order.compareTo(b.order));
      _changeEp(nextEp.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已经是最后一章了')),
      );
    }
  }

  void _changeEp(Ep ep) {
    setState(() {
      _currentEp = ep;
      _currentIndex = 0;
    });
    _pageController.jumpToPage(0);
    _loadPictures();
  }

  void _showEpSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                '选择章节',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.epList.length,
                itemBuilder: (context, index) {
                  final ep = widget.epList[index];
                  final isCurrentEp = ep.id == _currentEp.id;
                  return ListTile(
                    title: Text(
                      ep.title,
                      style: TextStyle(
                        color: isCurrentEp
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight: isCurrentEp ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: isCurrentEp
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (!isCurrentEp) {
                        _changeEp(ep);
                      }
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

  void _showSlider() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_currentIndex + 1} / ${_pictures.length}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Slider(
              value: _currentIndex.toDouble(),
              min: 0,
              max: (_pictures.length - 1).toDouble(),
              divisions: _pictures.length > 1 ? _pictures.length - 1 : 1,
              label: '${_currentIndex + 1}',
              onChanged: (value) {
                final index = value.round();
                setState(() {
                  _currentIndex = index;
                });
                _pageController.jumpToPage(index);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullScreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.comicTitle,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _currentEp.title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.list),
                  onPressed: _showEpSelector,
                  tooltip: '章节列表',
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  onPressed: _toggleFullScreen,
                  tooltip: '全屏',
                ),
              ],
            ),
      body: _buildBody(),
      bottomNavigationBar: _fullScreen
          ? null
          : _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
            ),
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
              onPressed: _loadPictures,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_pictures.isEmpty) {
      return const Center(
        child: Text(
          '暂无图片',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: _toggleFullScreen,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _pictures.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              // 重置缩放
              _transformController.value = Matrix4.identity();
            },
            itemBuilder: (context, index) {
              final picture = _pictures[index];
              final imageUrl = getImageUrl(picture.media);
              
              return InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '${index + 1} / ${_pictures.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.broken_image,
                            size: 60,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '图片加载失败\n${index + 1} / ${_pictures.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // 左右区域点击翻页
          Positioned.fill(
            child: Row(
              children: [
                // 左侧区域 - 上一页
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: () {
                      if (_currentIndex > 0) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // 中间区域 - 切换全屏
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _toggleFullScreen,
                    behavior: HitTestBehavior.translucent,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // 右侧区域 - 下一页
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: () {
                      if (_currentIndex < _pictures.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          if (_pictures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_currentIndex + 1}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Expanded(
                    child: Slider(
                      value: _currentIndex.toDouble(),
                      min: 0,
                      max: (_pictures.length - 1).toDouble(),
                      onChanged: (value) {
                        final index = value.round();
                        _pageController.jumpToPage(index);
                      },
                    ),
                  ),
                  Text(
                    '${_pictures.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                onPressed: _goToPreviousEp,
                tooltip: '上一章',
              ),
              IconButton(
                icon: const Icon(Icons.list, color: Colors.white),
                onPressed: _showEpSelector,
                tooltip: '章节列表',
              ),
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.white),
                onPressed: _showSlider,
                tooltip: '跳页',
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white),
                onPressed: _goToNextEp,
                tooltip: '下一章',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
