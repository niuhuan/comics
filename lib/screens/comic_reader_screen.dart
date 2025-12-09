import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/api/property_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/cached_image_widget.dart';
import 'package:comics/src/image_cache_manager.dart';
import 'comics_screen.dart' show getImageUrl;

/// 阅读器模式
enum ReaderMode {
  webtoon,        // 上下滚动（默认，适合条漫）
  webtoonZoom,    // WebToon 双击放大
  gallery,        // 相册模式（左右翻页，适合页漫）
  webtoonFreeZoom, // WebToon ListView双击放大
  twoPageGallery,  // 双页模式（实验性）
}

/// 阅读方向
enum ReaderDirection {
  topToBottom,    // 从上到下
  leftToRight,    // 从左到右
  rightToLeft,    // 从右到左
}

/// 双页方向
enum TwoPageDirection {
  leftToRight,    // 左到右
  rightToLeft,    // 右到左
}

/// 全屏操作模式
enum FullScreenAction {
  touchOnce,           // 点击屏幕一次全屏
  controller,          // 使用控制器全屏
  touchDouble,         // 双击屏幕全屏
  touchDoubleOnceNext, // 双击屏幕全屏 + 单击屏幕下一页
  threeArea,           // 将屏幕划分成三个区域 (上一页, 下一页, 全屏)
}

/// 进度条位置
enum ReaderSliderPosition {
  bottom,  // 底部
  right,   // 右侧
  left,    // 左侧
}

extension ReaderModeExtension on ReaderMode {
  String get displayName {
    switch (this) {
      case ReaderMode.webtoon:
        return '上下滚动';
      case ReaderMode.webtoonZoom:
        return '上下滚动（双击放大）';
      case ReaderMode.gallery:
        return '相册模式';
      case ReaderMode.webtoonFreeZoom:
        return '上下滚动（自由缩放）';
      case ReaderMode.twoPageGallery:
        return '双页模式';
    }
  }
  
  IconData get icon {
    switch (this) {
      case ReaderMode.webtoon:
        return Icons.view_day;
      case ReaderMode.webtoonZoom:
        return Icons.zoom_in;
      case ReaderMode.gallery:
        return Icons.view_carousel;
      case ReaderMode.webtoonFreeZoom:
        return Icons.zoom_out_map;
      case ReaderMode.twoPageGallery:
        return Icons.view_agenda;
    }
  }
}

extension ReaderDirectionExtension on ReaderDirection {
  String get displayName {
    switch (this) {
      case ReaderDirection.topToBottom:
        return '从上到下';
      case ReaderDirection.leftToRight:
        return '从左到右';
      case ReaderDirection.rightToLeft:
        return '从右到左';
    }
  }
}

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
  ReaderMode _readerMode = ReaderMode.webtoon;
  ReaderDirection _readerDirection = ReaderDirection.topToBottom;
  TwoPageDirection _twoPageDirection = TwoPageDirection.leftToRight;
  FullScreenAction _fullScreenAction = FullScreenAction.touchOnce;
  ReaderSliderPosition _sliderPosition = ReaderSliderPosition.bottom;
  bool _sliderDragging = false;
  
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  final TransformationController _transformController = TransformationController();
  
  // 翻页防抖时间戳
  int _pageControllerTime = 0;
  
  // 是否禁用动画
  bool _noAnimation = false;
  
  // 用于区分单击和双击的标志
  bool _isDoubleTap = false;
  Timer? _singleTapTimer;

  @override
  void initState() {
    super.initState();
    _currentEp = widget.currentEp;
    _loadReaderSettings();
    _loadPictures();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    _transformController.dispose();
    _singleTapTimer?.cancel();
    // 退出时恢复系统 UI
    if (_fullScreen) {
      _exitFullScreen();
    }
    super.dispose();
  }
  
  Future<void> _loadReaderSettings() async {
    try {
      // 加载阅读器模式
      final modeStr = await loadAppSetting(key: 'reader_mode');
      if (modeStr != null) {
        final modeIndex = int.tryParse(modeStr) ?? 0;
        if (modeIndex >= 0 && modeIndex < ReaderMode.values.length) {
          setState(() {
            _readerMode = ReaderMode.values[modeIndex];
          });
        }
      }
      
      // 加载阅读方向
      final directionStr = await loadAppSetting(key: 'reader_direction');
      if (directionStr != null) {
        final directionIndex = int.tryParse(directionStr) ?? 0;
        if (directionIndex >= 0 && directionIndex < ReaderDirection.values.length) {
          setState(() {
            _readerDirection = ReaderDirection.values[directionIndex];
          });
        }
      }
      
      // 加载双页方向
      final twoPageStr = await loadAppSetting(key: 'two_page_direction');
      if (twoPageStr != null) {
        final twoPageIndex = int.tryParse(twoPageStr) ?? 0;
        if (twoPageIndex >= 0 && twoPageIndex < TwoPageDirection.values.length) {
          setState(() {
            _twoPageDirection = TwoPageDirection.values[twoPageIndex];
          });
        }
      }
      
      // 加载全屏操作模式
      final fullScreenStr = await loadAppSetting(key: 'full_screen_action');
      if (fullScreenStr != null) {
        final fullScreenIndex = int.tryParse(fullScreenStr) ?? 0;
        if (fullScreenIndex >= 0 && fullScreenIndex < FullScreenAction.values.length) {
          setState(() {
            _fullScreenAction = FullScreenAction.values[fullScreenIndex];
          });
        }
      }
      
      // 加载进度条位置
      final sliderStr = await loadAppSetting(key: 'reader_slider_position');
      if (sliderStr != null) {
        final sliderIndex = int.tryParse(sliderStr) ?? 0;
        if (sliderIndex >= 0 && sliderIndex < ReaderSliderPosition.values.length) {
          setState(() {
            _sliderPosition = ReaderSliderPosition.values[sliderIndex];
          });
        }
      }
      
      // 加载翻页动画设置
      final noAnimationStr = await loadAppSetting(key: 'reader_no_animation');
      if (noAnimationStr != null) {
        setState(() {
          _noAnimation = noAnimationStr == 'true';
        });
      }
    } catch (e) {
      // 忽略错误，使用默认值
    }
  }
  
  Future<void> _saveReaderMode(ReaderMode mode) async {
    try {
      await saveAppSetting(key: 'reader_mode', value: mode.index.toString());
    } catch (e) {
      // 忽略错误
    }
  }
  
  Future<void> _saveReaderDirection(ReaderDirection direction) async {
    try {
      await saveAppSetting(key: 'reader_direction', value: direction.index.toString());
    } catch (e) {
      // 忽略错误
    }
  }
  
  Future<void> _saveTwoPageDirection(TwoPageDirection direction) async {
    try {
      await saveAppSetting(key: 'two_page_direction', value: direction.index.toString());
    } catch (e) {
      // 忽略错误
    }
  }
  
  Future<void> _saveFullScreenAction(FullScreenAction action) async {
    try {
      await saveAppSetting(key: 'full_screen_action', value: action.index.toString());
    } catch (e) {
      // 忽略错误
    }
  }
  
  Future<void> _saveSliderPosition(ReaderSliderPosition position) async {
    try {
      await saveAppSetting(key: 'reader_slider_position', value: position.index.toString());
    } catch (e) {
      // 忽略错误
    }
  }
  
  Future<void> _saveNoAnimation(bool noAnimation) async {
    try {
      await saveAppSetting(key: 'reader_no_animation', value: noAnimation.toString());
    } catch (e) {
      // 保存失败，恢复原状态
      if (mounted) {
        setState(() {
          _noAnimation = !noAnimation;
        });
      }
    }
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

      final initIndex = widget.initPosition ?? 0;
      setState(() {
        _pictures = allPictures;
        _loading = false;
        _currentIndex = initIndex;
      });

      // 跳转到指定位置
      if (initIndex > 0 && initIndex < allPictures.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToIndex(initIndex);
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
                // 阅读模式切换按钮
                PopupMenuButton<ReaderMode>(
                  icon: Icon(_readerMode.icon),
                  tooltip: '阅读模式',
                  onSelected: (mode) {
                    setState(() {
                      _readerMode = mode;
                    });
                    _saveReaderMode(mode);
                    // 切换模式后重置位置
                    if (mode == ReaderMode.webtoon) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          // 计算大概的滚动位置
                          final screenHeight = MediaQuery.of(context).size.height;
                          _scrollController.jumpTo(_currentIndex * screenHeight * 0.8);
                        }
                      });
                    } else {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(_currentIndex);
                        }
                      });
                    }
                  },
                  itemBuilder: (context) => ReaderMode.values.map((mode) {
                    return PopupMenuItem<ReaderMode>(
                      value: mode,
                      child: Row(
                        children: [
                          Icon(
                            mode.icon,
                            color: mode == _readerMode
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            mode.displayName,
                            style: TextStyle(
                              color: mode == _readerMode
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              fontWeight: mode == _readerMode
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
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
      body: Stack(
        children: [
          _buildBody(),
          if (_sliderDragging)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0x88000000),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "${_currentIndex + 1} / ${_pictures.length}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          _buildSideSlider(),
        ],
      ),
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

    // 根据阅读模式选择不同的布局
    switch (_readerMode) {
      case ReaderMode.webtoon:
        return _buildWebtoonReader();
      case ReaderMode.webtoonZoom:
        return _buildWebtoonZoomReader();
      case ReaderMode.gallery:
        return _buildGalleryReader();
      case ReaderMode.webtoonFreeZoom:
        return _buildWebtoonFreeZoomReader();
      case ReaderMode.twoPageGallery:
        return _buildTwoPageGalleryReader();
    }
  }

  /// 相册模式阅读器（Gallery 模式）
  Widget _buildGalleryReader() {
    final isHorizontal = _readerDirection != ReaderDirection.topToBottom;
    final reverse = _readerDirection == ReaderDirection.rightToLeft;
    
    Widget pageView = PageView.builder(
      controller: _pageController,
      scrollDirection: isHorizontal ? Axis.horizontal : Axis.vertical,
      reverse: reverse,
      itemCount: _pictures.length,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });
        // 重置缩放
        _transformController.value = Matrix4.identity();
        // 预加载相邻图片
        _preloadImages(index);
      },
      itemBuilder: (context, index) {
        return _buildImageItem(index);
      },
    );
    
    // 根据全屏模式包装手势
    Widget content = _buildFullScreenGesture(child: pageView);
    
    // 三区域控制需要覆盖在最上层
    if (_fullScreenAction == FullScreenAction.threeArea) {
      content = Stack(
        children: [
          content,
          _buildThreeAreaController(),
        ],
      );
    }
    
    return content;
  }
  
  /// 三区域控制器
  Widget _buildThreeAreaController() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isHorizontal = _readerDirection != ReaderDirection.topToBottom;
        final reverse = _readerDirection == ReaderDirection.rightToLeft;
        
        // 上一页区域
        final previousArea = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              // 防抖检查
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now < _pageControllerTime + 400) {
                return;
              }
              _pageControllerTime = now;
              _goToPreviousPage();
            },
            child: Container(color: Colors.transparent),
          ),
        );
        
        // 全屏区域
        final fullScreenArea = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleFullScreen,
            child: Container(color: Colors.transparent),
          ),
        );
        
        // 下一页区域
        final nextArea = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              // 防抖检查
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now < _pageControllerTime + 400) {
                return;
              }
              _pageControllerTime = now;
              _goToNextPage();
            },
            child: Container(color: Colors.transparent),
          ),
        );
        
        Widget child;
        if (isHorizontal) {
          // 水平方向
          if (reverse) {
            // 右到左：需要交换左右区域
            child = Row(children: [nextArea, fullScreenArea, previousArea]);
          } else {
            // 左到右：正常布局
            child = Row(children: [previousArea, fullScreenArea, nextArea]);
          }
        } else {
          // 垂直方向：上（上一页）、中（全屏）、下（下一页）
          child = Column(children: [previousArea, fullScreenArea, nextArea]);
        }
        
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: child,
        );
      },
    );
  }
  
  /// 根据全屏操作模式构建手势
  Widget _buildFullScreenGesture({required Widget child}) {
    switch (_fullScreenAction) {
      case FullScreenAction.touchOnce:
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleFullScreen,
          child: child,
        );
      case FullScreenAction.touchDouble:
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTap: _toggleFullScreen,
          child: child,
        );
      case FullScreenAction.touchDoubleOnceNext:
        // 使用 GestureDetector 处理单击和双击
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            // 取消之前的定时器
            _singleTapTimer?.cancel();
            // 如果不是双击，延迟执行单击操作
            if (!_isDoubleTap) {
              _singleTapTimer = Timer(const Duration(milliseconds: 200), () {
                if (mounted && !_isDoubleTap) {
                  _goToNextPage();
                }
                _isDoubleTap = false;
              });
            } else {
              _isDoubleTap = false;
            }
          },
          onDoubleTap: () {
            // 取消单击定时器
            _singleTapTimer?.cancel();
            _isDoubleTap = true;
            _toggleFullScreen();
          },
          child: child,
        );
      case FullScreenAction.controller:
      case FullScreenAction.threeArea:
        return child;
    }
  }
  
  /// 翻到下一页
  void _goToNextPage() {
    // 防抖检查
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _pageControllerTime + 400) {
      return;
    }
    _pageControllerTime = now;
    
    if (_readerMode == ReaderMode.webtoon || 
        _readerMode == ReaderMode.webtoonZoom ||
        _readerMode == ReaderMode.webtoonFreeZoom) {
      // Webtoon 模式：向下滚动一屏
      if (_scrollController.hasClients) {
        final isVertical = _readerDirection == ReaderDirection.topToBottom;
        final screenSize = isVertical 
            ? MediaQuery.of(context).size.height
            : MediaQuery.of(context).size.width;
        final currentOffset = _scrollController.offset;
        final targetOffset = currentOffset + screenSize * 0.9;
        
        if (targetOffset > _scrollController.position.maxScrollExtent) {
          if (_noAnimation) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          } else {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        } else {
          if (_noAnimation) {
            _scrollController.jumpTo(targetOffset);
          } else {
            _scrollController.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      }
    } else {
      // Gallery 模式：翻到下一页
      if (_pageController.hasClients && _currentIndex < _pictures.length - 1) {
        final isHorizontal = _readerDirection != ReaderDirection.topToBottom;
        final reverse = _readerDirection == ReaderDirection.rightToLeft;
        
        // 根据方向判断下一页
        if (isHorizontal) {
          if (reverse) {
            // 右到左：左侧是下一页
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: _noAnimation ? Duration.zero : const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          } else {
            // 左到右：右侧是下一页
            if (_currentIndex < _pictures.length - 1) {
              _pageController.nextPage(
                duration: _noAnimation ? Duration.zero : const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          }
        } else {
          // 垂直方向：向下是下一页
          if (_currentIndex < _pictures.length - 1) {
            _pageController.nextPage(
              duration: _noAnimation ? Duration.zero : const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      }
    }
  }
  
  /// 翻到上一页
  void _goToPreviousPage() {
    if (_readerMode == ReaderMode.webtoon || 
        _readerMode == ReaderMode.webtoonZoom ||
        _readerMode == ReaderMode.webtoonFreeZoom) {
      // Webtoon 模式：向上滚动一屏
      if (_scrollController.hasClients) {
        final isVertical = _readerDirection == ReaderDirection.topToBottom;
        final screenSize = isVertical 
            ? MediaQuery.of(context).size.height
            : MediaQuery.of(context).size.width;
        final currentOffset = _scrollController.offset;
        final targetOffset = currentOffset - screenSize * 0.9;
        
        if (targetOffset < 0) {
          if (_noAnimation) {
            _scrollController.jumpTo(0);
          } else {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        } else {
          if (_noAnimation) {
            _scrollController.jumpTo(targetOffset);
          } else {
            _scrollController.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      }
    } else {
      // Gallery 模式：翻到上一页
      if (_pageController.hasClients && _currentIndex > 0) {
        final isHorizontal = _readerDirection != ReaderDirection.topToBottom;
        final reverse = _readerDirection == ReaderDirection.rightToLeft;
        
        // 根据方向判断上一页
        if (isHorizontal) {
          if (reverse) {
            // 右到左：右侧是上一页
            if (_currentIndex < _pictures.length - 1) {
              _pageController.nextPage(
                duration: _noAnimation ? Duration.zero : const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          } else {
            // 左到右：左侧是上一页
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: _noAnimation ? Duration.zero : const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          }
        } else {
          // 垂直方向：向上是上一页
          if (_currentIndex > 0) {
            _pageController.previousPage(
              duration: _noAnimation ? Duration.zero : const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
      }
    }
  }
  
  /// 预加载图片
  void _preloadImages(int currentIndex) {
    // 预加载前后各2张图片（使用自定义缓存）
    final cacheManager = ImageCacheManager();
    for (int i = currentIndex - 2; i <= currentIndex + 2; i++) {
      if (i >= 0 && i < _pictures.length && i != currentIndex) {
        final picture = _pictures[i];
        final imageUrl = getImageUrl(picture.media);
        // 使用自定义缓存预加载
        cacheManager.cacheImage(
          widget.moduleId,
          imageUrl,
          headers: picture.media.headers,
        ).catchError((e) {
          // 忽略预加载错误
          return null;
        });
      }
    }
  }

  /// 上下滚动阅读器（Webtoon 模式）
  Widget _buildWebtoonReader() {
    final isVertical = _readerDirection == ReaderDirection.topToBottom;
    
    Widget listView = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // 更新当前索引（基于滚动位置）
          _updateCurrentIndexFromScroll();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
        reverse: _readerDirection == ReaderDirection.rightToLeft,
        itemCount: _pictures.length,
        itemBuilder: (context, index) {
          return _buildWebtoonImageItem(index);
        },
      ),
    );
    
    // 根据全屏模式包装手势
    Widget content = _buildFullScreenGesture(child: listView);
    
    // 三区域控制需要覆盖在最上层
    if (_fullScreenAction == FullScreenAction.threeArea) {
      content = Stack(
        children: [
          content,
          _buildThreeAreaController(),
        ],
      );
    }
    
    return content;
  }
  
  /// WebToon 模式图片项
  Widget _buildWebtoonImageItem(int index) {
    final picture = _pictures[index];
    final isVertical = _readerDirection == ReaderDirection.topToBottom;
    
    return CachedImageWidget(
      imageInfo: picture.media,
      moduleId: widget.moduleId,
      fit: isVertical ? BoxFit.fitWidth : BoxFit.fitHeight,
      width: isVertical ? double.infinity : null,
      height: isVertical ? null : double.infinity,
      placeholder: Container(
        height: isVertical ? 300 : null,
        width: isVertical ? null : 300,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              '${index + 1} / ${_pictures.length}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
      errorWidget: Container(
        height: isVertical ? 300 : null,
        width: isVertical ? null : 300,
        alignment: Alignment.center,
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
    );
  }
  
  /// WebToon 双击放大模式
  Widget _buildWebtoonZoomReader() {
    final isVertical = _readerDirection == ReaderDirection.topToBottom;
    
    Widget listView = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _updateCurrentIndexFromScroll();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
        reverse: _readerDirection == ReaderDirection.rightToLeft,
        itemCount: _pictures.length,
        itemBuilder: (context, index) {
          return _buildWebtoonImageItem(index);
        },
      ),
    );
    
    // 双击放大功能（使用 InteractiveViewer 包装）
    Widget content = GestureDetector(
      onDoubleTap: _toggleFullScreen,
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1.0,
        maxScale: 3.0,
        child: listView,
      ),
    );
    
    // 根据全屏模式包装手势
    if (_fullScreenAction == FullScreenAction.touchOnce) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleFullScreen,
        child: content,
      );
    }
    
    // 三区域控制需要覆盖在最上层
    if (_fullScreenAction == FullScreenAction.threeArea) {
      content = Stack(
        children: [
          content,
          _buildThreeAreaController(),
        ],
      );
    }
    
    return content;
  }
  
  /// WebToon 自由缩放模式
  Widget _buildWebtoonFreeZoomReader() {
    final isVertical = _readerDirection == ReaderDirection.topToBottom;
    
    Widget listView = ListView.builder(
      controller: _scrollController,
      scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
      reverse: _readerDirection == ReaderDirection.rightToLeft,
      itemCount: _pictures.length,
      itemBuilder: (context, index) {
        return _buildWebtoonImageItem(index);
      },
    );
    
    Widget content = InteractiveViewer(
      transformationController: _transformController,
      minScale: 1.0,
      maxScale: 2.0,
      child: listView,
    );
    
    // 根据全屏模式包装手势
    if (_fullScreenAction == FullScreenAction.touchDouble) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _toggleFullScreen,
        child: content,
      );
    } else if (_fullScreenAction == FullScreenAction.touchDoubleOnceNext) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // 取消之前的定时器
          _singleTapTimer?.cancel();
          // 如果不是双击，延迟执行单击操作
          if (!_isDoubleTap) {
            _singleTapTimer = Timer(const Duration(milliseconds: 200), () {
              if (mounted && !_isDoubleTap) {
                _goToNextPage();
              }
              _isDoubleTap = false;
            });
          } else {
            _isDoubleTap = false;
          }
        },
        onDoubleTap: () {
          // 取消单击定时器
          _singleTapTimer?.cancel();
          _isDoubleTap = true;
          _toggleFullScreen();
        },
        child: content,
      );
    }
    
    // 三区域控制需要覆盖在最上层
    if (_fullScreenAction == FullScreenAction.threeArea) {
      content = Stack(
        children: [
          content,
          _buildThreeAreaController(),
        ],
      );
    }
    
    return content;
  }
  
  /// 双页模式阅读器
  Widget _buildTwoPageGalleryReader() {
    final isHorizontal = _readerDirection != ReaderDirection.topToBottom;
    final reverse = _readerDirection == ReaderDirection.rightToLeft;
    
    Widget pageView = PageView.builder(
      controller: _pageController,
      scrollDirection: isHorizontal ? Axis.horizontal : Axis.vertical,
      reverse: reverse,
      itemCount: (_pictures.length / 2).ceil(),
      onPageChanged: (pageIndex) {
        final imageIndex = pageIndex * 2;
        setState(() {
          _currentIndex = imageIndex;
        });
        _transformController.value = Matrix4.identity();
        // 预加载相邻图片
        _preloadImages(imageIndex);
      },
      itemBuilder: (context, pageIndex) {
        final leftIndex = pageIndex * 2;
        final rightIndex = leftIndex + 1;
        
        // 根据双页方向决定左右顺序
        final firstIndex = _twoPageDirection == TwoPageDirection.leftToRight 
            ? leftIndex 
            : (rightIndex < _pictures.length ? rightIndex : leftIndex);
        final secondIndex = _twoPageDirection == TwoPageDirection.leftToRight
            ? (rightIndex < _pictures.length ? rightIndex : null)
            : leftIndex;
        
        return Row(
          children: [
            Expanded(
              child: _buildImageItem(
                firstIndex,
                fit: BoxFit.contain,
              ),
            ),
            Expanded(
              child: secondIndex != null
                  ? _buildImageItem(
                      secondIndex,
                      fit: BoxFit.contain,
                    )
                  : Container(
                      color: Colors.black,
                      child: const Center(
                        child: Text(
                          '空白页',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
    
    // 根据全屏模式包装手势
    Widget content = _buildFullScreenGesture(child: pageView);
    
    // 三区域控制需要覆盖在最上层
    if (_fullScreenAction == FullScreenAction.threeArea) {
      content = Stack(
        children: [
          content,
          _buildThreeAreaController(),
        ],
      );
    }
    
    return content;
  }

  void _updateCurrentIndexFromScroll() {
    if (!_scrollController.hasClients) return;
    
    // 简单估算当前索引
    final offset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;
    final estimatedIndex = (offset / (viewportHeight * 0.8)).round();
    
    if (estimatedIndex >= 0 && estimatedIndex < _pictures.length) {
      if (_currentIndex != estimatedIndex) {
        setState(() {
          _currentIndex = estimatedIndex;
        });
      }
    }
  }

  /// 构建单个图片项
  Widget _buildImageItem(int index, {BoxFit fit = BoxFit.contain}) {
    if (index < 0 || index >= _pictures.length) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            '图片不存在',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    final picture = _pictures[index];
    
    // 在 touchDoubleOnceNext 模式下，如果图片没有缩放，禁用平移以允许手势传递
    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final isScaled = scale > 1.01; // 允许小的误差
    final panEnabled = _fullScreenAction != FullScreenAction.touchDoubleOnceNext || isScaled;
    
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 4.0,
      panEnabled: panEnabled,
      child: Center(
        child: CachedImageWidget(
          imageInfo: picture.media,
          moduleId: widget.moduleId,
          fit: fit,
          placeholder: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  '${index + 1} / ${_pictures.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          errorWidget: Center(
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
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    // 重新加载图片
                    setState(() {});
                  },
                  child: const Text('重试', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_sliderPosition != ReaderSliderPosition.bottom) {
      return Container();
    }
    
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          if (_pictures.isNotEmpty && _readerMode != ReaderMode.webtoonFreeZoom)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_currentIndex + 1}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTapDown: (_) {
                        setState(() {
                          _sliderDragging = true;
                        });
                      },
                      onTapUp: (_) {
                        setState(() {
                          _sliderDragging = false;
                        });
                      },
                      child: Slider(
                        value: _currentIndex.toDouble(),
                        min: 0,
                        max: (_pictures.length - 1).toDouble(),
                        onChanged: (value) {
                          final index = value.round();
                          setState(() {
                            _currentIndex = index;
                            _sliderDragging = true;
                          });
                        },
                        onChangeEnd: (value) {
                          setState(() {
                            _sliderDragging = false;
                          });
                          _jumpToIndex(value.round());
                        },
                      ),
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
              // 阅读模式按钮
              IconButton(
                icon: Icon(_readerMode.icon, color: Colors.white),
                onPressed: _showReaderModeSelector,
                tooltip: '阅读模式',
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: _showSettingsPanel,
                tooltip: '设置',
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
  
  /// 构建侧边进度条
  Widget _buildSideSlider() {
    if (_sliderPosition == ReaderSliderPosition.bottom || _fullScreen) {
      return Container();
    }
    
    if (_pictures.isEmpty || _readerMode == ReaderMode.webtoonFreeZoom) {
      return Container();
    }
    
    final isRight = _sliderPosition == ReaderSliderPosition.right;
    
    return Align(
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 35,
          height: 300,
          decoration: BoxDecoration(
            color: const Color(0x66000000),
            borderRadius: BorderRadius.only(
              topLeft: isRight ? const Radius.circular(10) : Radius.zero,
              topRight: isRight ? Radius.zero : const Radius.circular(10),
              bottomLeft: isRight ? const Radius.circular(10) : Radius.zero,
              bottomRight: isRight ? Radius.zero : const Radius.circular(10),
            ),
          ),
          padding: const EdgeInsets.only(top: 10, bottom: 10, left: 6, right: 6),
          child: RotatedBox(
            quarterTurns: 3,
            child: GestureDetector(
              onTapDown: (_) {
                setState(() {
                  _sliderDragging = true;
                });
              },
              onTapUp: (_) {
                setState(() {
                  _sliderDragging = false;
                });
              },
              child: Slider(
                value: _currentIndex.toDouble(),
                min: 0,
                max: (_pictures.length - 1).toDouble(),
                onChanged: (value) {
                  final index = value.round();
                  setState(() {
                    _currentIndex = index;
                    _sliderDragging = true;
                  });
                },
                onChangeEnd: (value) {
                  setState(() {
                    _sliderDragging = false;
                  });
                  _jumpToIndex(value.round());
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 跳转到指定索引
  void _jumpToIndex(int index) {
    if (index < 0 || index >= _pictures.length) return;
    
    if (_readerMode == ReaderMode.webtoon || 
        _readerMode == ReaderMode.webtoonZoom ||
        _readerMode == ReaderMode.webtoonFreeZoom) {
      // Webtoon 模式：滚动到估算位置
      if (_scrollController.hasClients) {
        final viewportHeight = _scrollController.position.viewportDimension;
        final isVertical = _readerDirection == ReaderDirection.topToBottom;
        final scrollSize = isVertical ? viewportHeight : MediaQuery.of(context).size.width;
        final targetOffset = index * scrollSize * 0.8;
        if (_noAnimation) {
          _scrollController.jumpTo(targetOffset);
        } else {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    } else if (_readerMode == ReaderMode.twoPageGallery) {
      // 双页模式：跳转到对应页面
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index ~/ 2);
      }
    } else {
      // Gallery 模式：跳转到页面
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
    }
    
    setState(() {
      _currentIndex = index;
    });
  }

  /// 显示阅读模式选择器
  void _showReaderModeSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择阅读模式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...ReaderMode.values.map((mode) {
              final isSelected = mode == _readerMode;
              return ListTile(
                leading: Icon(
                  mode.icon,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(
                  mode.displayName,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  if (!isSelected) {
                    setState(() {
                      _readerMode = mode;
                    });
                    _saveReaderMode(mode);
                    // 切换模式后重置位置
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mode == ReaderMode.webtoon || 
                          mode == ReaderMode.webtoonZoom ||
                          mode == ReaderMode.webtoonFreeZoom) {
                        if (_scrollController.hasClients) {
                          final screenHeight = MediaQuery.of(context).size.height;
                          _scrollController.jumpTo(_currentIndex * screenHeight * 0.8);
                        }
                      } else {
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(_currentIndex);
                        }
                      }
                    });
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }
  
  /// 显示设置面板
  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xAA000000),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: ListView(
          children: [
            // 阅读方向
            ListTile(
              leading: const Icon(Icons.swap_vert, color: Colors.white),
              title: const Text('阅读方向', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _readerDirection.displayName,
                style: const TextStyle(color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDirectionSelector();
              },
            ),
            // 全屏操作
            ListTile(
              leading: const Icon(Icons.touch_app, color: Colors.white),
              title: const Text('全屏操作', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _getFullScreenActionName(),
                style: const TextStyle(color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(context);
                _showFullScreenActionSelector();
              },
            ),
            // 进度条位置
            ListTile(
              leading: const Icon(Icons.tune, color: Colors.white),
              title: const Text('进度条位置', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _getSliderPositionName(),
                style: const TextStyle(color: Colors.grey),
              ),
              onTap: () {
                Navigator.pop(context);
                _showSliderPositionSelector();
              },
            ),
            // 双页方向（仅双页模式显示）
            if (_readerMode == ReaderMode.twoPageGallery)
              ListTile(
                leading: const Icon(Icons.view_agenda, color: Colors.white),
                title: const Text('双页方向', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _twoPageDirection == TwoPageDirection.leftToRight
                      ? '左到右'
                      : '右到左',
                  style: const TextStyle(color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showTwoPageDirectionSelector();
                },
              ),
            // 翻页动画开关
            ListTile(
              leading: const Icon(Icons.animation, color: Colors.white),
              title: const Text('翻页动画', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _noAnimation ? '已关闭' : '已开启',
                style: const TextStyle(color: Colors.grey),
              ),
              trailing: Switch(
                value: !_noAnimation,
                onChanged: (value) async {
                  final newNoAnimation = !value;
                  setState(() {
                    _noAnimation = newNoAnimation;
                  });
                  await _saveNoAnimation(newNoAnimation);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getFullScreenActionName() {
    switch (_fullScreenAction) {
      case FullScreenAction.touchOnce:
        return '点击屏幕一次全屏';
      case FullScreenAction.controller:
        return '使用控制器全屏';
      case FullScreenAction.touchDouble:
        return '双击屏幕全屏';
      case FullScreenAction.touchDoubleOnceNext:
        return '双击全屏 + 单击下一页';
      case FullScreenAction.threeArea:
        return '三区域控制';
    }
  }
  
  String _getSliderPositionName() {
    switch (_sliderPosition) {
      case ReaderSliderPosition.bottom:
        return '底部';
      case ReaderSliderPosition.right:
        return '右侧';
      case ReaderSliderPosition.left:
        return '左侧';
    }
  }
  
  void _showDirectionSelector() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择阅读方向'),
        children: ReaderDirection.values.map((direction) {
          final isSelected = direction == _readerDirection;
          return SimpleDialogOption(
            child: Text(
              direction.displayName,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              if (!isSelected) {
                setState(() {
                  _readerDirection = direction;
                });
                _saveReaderDirection(direction);
              }
            },
          );
        }).toList(),
      ),
    );
  }
  
  void _showFullScreenActionSelector() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择全屏操作'),
        children: FullScreenAction.values.map((action) {
          final isSelected = action == _fullScreenAction;
          return SimpleDialogOption(
            child: Text(
              _getFullScreenActionNameForAction(action),
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              if (!isSelected) {
                setState(() {
                  _fullScreenAction = action;
                });
                _saveFullScreenAction(action);
              }
            },
          );
        }).toList(),
      ),
    );
  }
  
  String _getFullScreenActionNameForAction(FullScreenAction action) {
    switch (action) {
      case FullScreenAction.touchOnce:
        return '点击屏幕一次全屏';
      case FullScreenAction.controller:
        return '使用控制器全屏';
      case FullScreenAction.touchDouble:
        return '双击屏幕全屏';
      case FullScreenAction.touchDoubleOnceNext:
        return '双击全屏 + 单击下一页';
      case FullScreenAction.threeArea:
        return '三区域控制';
    }
  }
  
  void _showSliderPositionSelector() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择进度条位置'),
        children: ReaderSliderPosition.values.map((position) {
          final isSelected = position == _sliderPosition;
          return SimpleDialogOption(
            child: Text(
              _getSliderPositionNameForPosition(position),
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              if (!isSelected) {
                setState(() {
                  _sliderPosition = position;
                });
                _saveSliderPosition(position);
              }
            },
          );
        }).toList(),
      ),
    );
  }
  
  String _getSliderPositionNameForPosition(ReaderSliderPosition position) {
    switch (position) {
      case ReaderSliderPosition.bottom:
        return '底部';
      case ReaderSliderPosition.right:
        return '右侧';
      case ReaderSliderPosition.left:
        return '左侧';
    }
  }
  
  void _showTwoPageDirectionSelector() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择双页方向'),
        children: TwoPageDirection.values.map((direction) {
          final isSelected = direction == _twoPageDirection;
          return SimpleDialogOption(
            child: Text(
              direction == TwoPageDirection.leftToRight ? '左到右' : '右到左',
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              if (!isSelected) {
                setState(() {
                  _twoPageDirection = direction;
                });
                _saveTwoPageDirection(direction);
              }
            },
          );
        }).toList(),
      ),
    );
  }
}
