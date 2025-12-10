import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:event/event.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/api/property_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/cached_image_widget.dart';
import 'package:comics/src/image_cache_manager.dart';
import 'package:comics/src/gesture_zoom_box.dart';
import 'comics_screen.dart' show getImageUrl;

///////////////////////////////////////////////////////////////////////////////
// 事件系统

Event<_ReaderControllerEventArgs> _readerControllerEvent =
    Event<_ReaderControllerEventArgs>();

class _ReaderControllerEventArgs extends EventArgs {
  final String key;

  _ReaderControllerEventArgs(this.key);
}

Widget readerKeyboardHolder(Widget widget) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    widget = RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent) {
          if (event.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
            _readerControllerEvent.broadcast(_ReaderControllerEventArgs("UP"));
          }
          if (event.isKeyPressed(LogicalKeyboardKey.arrowDown)) {
            _readerControllerEvent.broadcast(_ReaderControllerEventArgs("DOWN"));
          }
          if (event.isKeyPressed(LogicalKeyboardKey.arrowLeft)) {
            _readerControllerEvent.broadcast(_ReaderControllerEventArgs("LEFT"));
          }
          if (event.isKeyPressed(LogicalKeyboardKey.arrowRight)) {
            _readerControllerEvent.broadcast(_ReaderControllerEventArgs("RIGHT"));
          }
        }
      },
      child: widget,
    );
  }
  return widget;
}

///////////////////////////////////////////////////////////////////////////////

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
  final bool autoFullScreen;

  const ComicReaderScreen({
    super.key,
    required this.moduleId,
    required this.comicId,
    required this.comicTitle,
    required this.epList,
    required this.currentEp,
    this.initPosition,
    this.autoFullScreen = false,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late Ep _ep;
  bool _fullScreen = false;
  late Future<List<Picture>> _future;
  int? _lastChangeRank;
  bool _replacement = false;

  Future<List<Picture>> _load() async {
    // 加载所有页面的图片
    List<Picture> allPictures = [];
    int page = 1;
    int totalPages = 1;

    do {
      final picturePage = await getPictures(
        moduleId: widget.moduleId,
        comicId: widget.comicId,
        epId: _ep.id,
        page: page,
      );
      allPictures.addAll(picturePage.docs);
      totalPages = picturePage.pageInfo.pages;
      page++;
    } while (page <= totalPages);

    if (widget.autoFullScreen) {
      setState(() {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [],
        );
        _fullScreen = true;
      });
    }
    return allPictures;
  }

  Future _onPositionChange(int position) async {
    _lastChangeRank = position;
    // TODO: 保存阅读位置到历史记录
  }

  FutureOr<dynamic> _onChangeEp(int epOrder) {
    var orderMap = <int, Ep>{};
    for (var element in widget.epList) {
      orderMap[element.order] = element;
    }
    if (orderMap.containsKey(epOrder)) {
      _replacement = true;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => ComicReaderScreen(
            moduleId: widget.moduleId,
            comicId: widget.comicId,
            comicTitle: widget.comicTitle,
            epList: widget.epList,
            currentEp: orderMap[epOrder]!,
            autoFullScreen: _fullScreen,
          ),
        ),
      );
    }
  }

  FutureOr<dynamic> _onReloadEp() {
    _replacement = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => ComicReaderScreen(
          moduleId: widget.moduleId,
          comicId: widget.comicId,
          comicTitle: widget.comicTitle,
          epList: widget.epList,
          currentEp: _ep,
          initPosition: _lastChangeRank ?? widget.initPosition,
          autoFullScreen: _fullScreen,
        ),
      ),
    );
  }

  @override
  void initState() {
    // EP
    _ep = widget.currentEp;
    // INIT
    _future = _load();
    super.initState();
  }

  @override
  void dispose() {
    if (!_replacement) {
      // 恢复系统UI
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildScreen(context);
  }

  Widget buildScreen(BuildContext context) {
    return readerKeyboardHolder(_build(context));
  }

  Widget _build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<Picture>> snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: _fullScreen
                ? null
                : AppBar(
                    title: Text("${_ep.title} - ${widget.comicTitle}"),
                  ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('加载失败: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _future = _load();
                      });
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: _fullScreen
                ? null
                : AppBar(
                    title: Text("${_ep.title} - ${widget.comicTitle}"),
                  ),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        var epNameMap = <int, String>{};
        for (var element in widget.epList) {
          epNameMap[element.order] = element.title;
        }
        return Scaffold(
          // 让内容可以延伸到状态栏/APPBar区域，配合我们自定义叠加的 AppBar
          extendBodyBehindAppBar: true,
          body: ImageReader(
            ImageReaderStruct(
              moduleId: widget.moduleId,
              images: snapshot.data!,
              fullScreen: _fullScreen,
              onFullScreenChange: _onFullScreenChange,
              onPositionChange: _onPositionChange,
              initPosition: widget.initPosition,
              epNameMap: epNameMap,
              epOrder: _ep.order,
              comicTitle: widget.comicTitle,
              onChangeEp: _onChangeEp,
              onReloadEp: _onReloadEp,
            ),
          ),
        );
      },
    );
  }

  Future _onFullScreenChange(bool fullScreen) async {
    setState(() {
      if (fullScreen) {
        if (Platform.isAndroid || Platform.isIOS) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [],
          );
        }
      } else {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
      _fullScreen = fullScreen;
    });
  }
}

///////////////////////////////////////////////////////////////////////////////
// ImageReader 结构

class ImageReaderStruct {
  final String moduleId;
  final List<Picture> images;
  final bool fullScreen;
  final FutureOr<dynamic> Function(bool fullScreen) onFullScreenChange;
  final FutureOr<dynamic> Function(int) onPositionChange;
  final int? initPosition;
  final Map<int, String> epNameMap;
  final int epOrder;
  final String comicTitle;
  final FutureOr<dynamic> Function(int) onChangeEp;
  final FutureOr<dynamic> Function() onReloadEp;

  const ImageReaderStruct({
    required this.moduleId,
    required this.images,
    required this.fullScreen,
    required this.onFullScreenChange,
    required this.onPositionChange,
    this.initPosition,
    required this.epNameMap,
    required this.epOrder,
    required this.comicTitle,
    required this.onChangeEp,
    required this.onReloadEp,
  });
}

///////////////////////////////////////////////////////////////////////////////
// ImageReader 组件

class ImageReader extends StatefulWidget {
  final ImageReaderStruct struct;

  const ImageReader(this.struct, {super.key});

  @override
  State<StatefulWidget> createState() => _ImageReaderState();
}

class _ImageReaderState extends State<ImageReader> {
  // 记录初始方向
  final ReaderDirection _pagerDirection = ReaderDirection.topToBottom;

  // 记录初始阅读器类型
  ReaderMode _pagerType = ReaderMode.webtoon;

  // 记录了控制器
  FullScreenAction _fullScreenAction = FullScreenAction.touchOnce;

  bool _settingsLoaded = false;
  bool _noAnimation = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // 加载阅读器模式
    final modeStr = await loadAppSetting(key: 'reader_mode');
    int modeIndex = 0;
    if (modeStr != null) {
      modeIndex = int.tryParse(modeStr) ?? 0;
    }
    if (modeIndex >= 0 && modeIndex < ReaderMode.values.length) {
      _pagerType = ReaderMode.values[modeIndex];
    } else {
      _pagerType = ReaderMode.webtoon;
    }

    // 加载全屏操作模式
    final fullScreenStr = await loadAppSetting(key: 'full_screen_action');
    int fullScreenIndex = 0;
    if (fullScreenStr != null) {
      fullScreenIndex = int.tryParse(fullScreenStr) ?? 0;
    }
    if (fullScreenIndex >= 0 && fullScreenIndex < FullScreenAction.values.length) {
      _fullScreenAction = FullScreenAction.values[fullScreenIndex];
    } else {
      _fullScreenAction = FullScreenAction.touchOnce;
    }

    // 加载取消翻页动画
    final noAniStr = await loadAppSetting(key: 'no_animation');
    if (noAniStr != null) {
      _noAnimation = noAniStr == '1' || noAniStr.toLowerCase() == 'true';
    } else {
      _noAnimation = false;
    }

    setState(() {
      _settingsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return _ImageReaderContent(
      widget.struct,
      _pagerDirection,
      _pagerType,
      _fullScreenAction,
      _noAnimation,
    );
  }
}

///////////////////////////////////////////////////////////////////////////////
// ImageReaderContent

class _ImageReaderContent extends StatefulWidget {
  // 记录初始方向
  final ReaderDirection pagerDirection;

  // 记录初始阅读器类型
  final ReaderMode pagerType;

  final FullScreenAction fullScreenAction;

  // 是否取消翻页动画
  final bool noAnimation;

  final ImageReaderStruct struct;

  const _ImageReaderContent(
    this.struct,
    this.pagerDirection,
    this.pagerType,
    this.fullScreenAction,
    this.noAnimation,
  );

  @override
  State<StatefulWidget> createState() {
    switch (pagerType) {
      case ReaderMode.webtoon:
        return _WebToonReaderState();
      case ReaderMode.webtoonZoom:
        return _WebToonZoomReaderState();
      case ReaderMode.gallery:
        return _GalleryReaderState();
      case ReaderMode.webtoonFreeZoom:
        return _ListViewReaderState();
      case ReaderMode.twoPageGallery:
        return _TwoPageGalleryReaderState();
    }
  }
}
///////////////////////////////////////////////////////////////////////////////
// Abstract State

abstract class _ImageReaderContentState extends State<_ImageReaderContent> {
  bool _sliderDragging = false;

  // 阅读器
  Widget _buildViewer();

  Widget _buildViewerProcess() {
    return Stack(
      children: [
        _buildViewer(),
        if (_sliderDragging) _sliderDraggingText(),
      ],
    );
  }

  Widget _sliderDraggingText() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x88000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "${_slider + 1} / ${widget.struct.images.length}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
          ),
        ),
      ),
    );
  }

  // 键盘, 音量键 等事件
  void _needJumpTo(int index, bool animation);

  void _needScrollForward();

  void _needScrollBackward();

  @override
  void initState() {
    _initCurrent();
    _readerControllerEvent.subscribe(_onPageControl);
    super.initState();
  }

  @override
  void dispose() {
    _readerControllerEvent.unsubscribe(_onPageControl);
    super.dispose();
  }

  void _onPageControl(_ReaderControllerEventArgs? args) {
    if (args != null) {
      var event = args.key;
      switch (event) {
        case "UP":
          if (widget.pagerType == ReaderMode.webtoonFreeZoom) {
            _needScrollBackward();
            break;
          }
          if (_current > 0) {
            _needJumpTo(_current - 1, true);
          }
          break;
        case "DOWN":
          if (widget.pagerType == ReaderMode.webtoonFreeZoom) {
            _needScrollForward();
            break;
          }
          int point = 1;
          if (widget.pagerType == ReaderMode.twoPageGallery) {
            point = 2;
          }
          if (_current < widget.struct.images.length - point) {
            _needJumpTo(_current + point, true);
          }
          break;
        case "LEFT":
          if (_current > 0) {
            _needJumpTo(_current - 1, true);
          }
          break;
        case "RIGHT":
          int point = 1;
          if (widget.pagerType == ReaderMode.twoPageGallery) {
            point = 2;
          }
          if (_current < widget.struct.images.length - point) {
            _needJumpTo(_current + point, true);
          }
          break;
      }
    }
  }

  late int _startIndex;
  late int _current;
  late int _slider;

  void _initCurrent() {
    if (widget.struct.initPosition != null &&
        widget.struct.images.length > widget.struct.initPosition!) {
      _startIndex = widget.struct.initPosition!;
    } else {
      _startIndex = 0;
    }
    _current = _startIndex;
    _slider = _startIndex;
  }

  void _onCurrentChange(int index) {
    if (index != _current) {
      setState(() {
        _current = index;
        _slider = index;
        widget.struct.onPositionChange(index);
      });
    }
  }

  // 与显示有关的方法

  @override
  Widget build(BuildContext context) {
    switch (widget.fullScreenAction) {
      case FullScreenAction.controller:
        return _buildLayout(_buildFullScreenControllerStackItem());
      case FullScreenAction.touchOnce:
        return _buildLayout(
          _buildTouchOnceControllerAction(Container()),
        );
      case FullScreenAction.touchDouble:
        return _buildLayout(
          _buildTouchDoubleControllerAction(Container()),
        );
      case FullScreenAction.touchDoubleOnceNext:
        return _buildLayout(
          _buildTouchDoubleOnceNextControllerAction(Container()),
        );
      case FullScreenAction.threeArea:
        return _buildLayout(_buildThreeAreaControllerAction());
    }
  }

  Widget _buildLayout(Widget overlayChild) {
    return Stack(
      children: [
        _buildViewerProcess(),
        overlayChild,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildSliderBottom(),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildAppBar(),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    if (widget.struct.fullScreen) {
      return const SizedBox.shrink();
    }
    return AppBar(
      title: Text(widget.struct.comicTitle),
      actions: [
        IconButton(
          icon: const Icon(Icons.list),
          onPressed: _onChooseEp,
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: _onMoreSetting,
        ),
      ],
    );
  }

  Widget _buildSliderBottom() {
    if (widget.struct.fullScreen) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 45,
      color: const Color(0x88000000),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 15),
          Text(
            '${_slider + 1}',
            style: const TextStyle(color: Colors.white),
          ),
          Expanded(
            child: _buildSliderWidget(),
          ),
          Text(
            '${widget.struct.images.length}',
            style: const TextStyle(color: Colors.white),
          ),
          Container(width: 15),
        ],
      ),
    );
  }



  Widget _buildSliderWidget() {
    return Slider(
      min: 0,
      max: (widget.struct.images.length - 1).toDouble(),
      value: _slider.toDouble(),
      onChangeStart: (value) {
        setState(() {
          _sliderDragging = true;
        });
      },
      onChangeEnd: (value) {
        setState(() {
          _sliderDragging = false;
        });
      },
      onChanged: (value) {
        _slider = value.toInt();
        setState(() {});
      },
    );
  }

  Widget _buildFullScreenControllerStackItem() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0x88000000),
            ),
            child: GestureDetector(
              onTap: () {
                widget.struct.onFullScreenChange(!widget.struct.fullScreen);
              },
              child: Icon(
                widget.struct.fullScreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen_outlined,
                size: 30,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTouchOnceControllerAction(Widget child) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          widget.struct.onFullScreenChange(!widget.struct.fullScreen);
        },
        child: child,
      ),
    );
  }

  Widget _buildTouchDoubleControllerAction(Widget child) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: () {
          widget.struct.onFullScreenChange(!widget.struct.fullScreen);
        },
        child: child,
      ),
    );
  }

  Widget _buildTouchDoubleOnceNextControllerAction(Widget child) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // 下一页
          if (_current < widget.struct.images.length - 1) {
            _needJumpTo(_current + 1, true);
          } else {
            _onNextAction();
          }
        },
        onDoubleTap: () {
          widget.struct.onFullScreenChange(!widget.struct.fullScreen);
        },
        child: child,
      ),
    );
  }

  Widget _buildThreeAreaControllerAction() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final areaSize = 0.3; // 30% on each side

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (TapUpDetails details) {
              final position = details.localPosition;

            if (widget.pagerDirection == ReaderDirection.topToBottom) {
              // 垂直方向
              if (position.dy < height * areaSize) {
                // 上方区域 - 上一页
                if (_current > 0) {
                  _needJumpTo(_current - 1, true);
                }
              } else if (position.dy > height * (1 - areaSize)) {
                // 下方区域 - 下一页
                if (_current < widget.struct.images.length - 1) {
                  _needJumpTo(_current + 1, true);
                } else {
                  _onNextAction();
                }
              } else {
                // 中间区域 - 全屏切换
                widget.struct.onFullScreenChange(!widget.struct.fullScreen);
              }
            } else {
              // 水平方向
              final isRTL = widget.pagerDirection == ReaderDirection.rightToLeft;
              if (position.dx < width * areaSize) {
                // 左侧区域
                if (isRTL) {
                  // 右到左模式，左侧是下一页
                  if (_current < widget.struct.images.length - 1) {
                    _needJumpTo(_current + 1, true);
                  } else {
                    _onNextAction();
                  }
                } else {
                  // 左到右模式，左侧是上一页
                  if (_current > 0) {
                    _needJumpTo(_current - 1, true);
                  }
                }
              } else if (position.dx > width * (1 - areaSize)) {
                // 右侧区域
                if (isRTL) {
                  // 右到左模式，右侧是上一页
                  if (_current > 0) {
                    _needJumpTo(_current - 1, true);
                  }
                } else {
                  // 左到右模式，右侧是下一页
                  if (_current < widget.struct.images.length - 1) {
                    _needJumpTo(_current + 1, true);
                  } else {
                    _onNextAction();
                  }
                }
              } else {
                // 中间区域 - 全屏切换
                widget.struct.onFullScreenChange(!widget.struct.fullScreen);
              }
            }
          },
          child: Container(),
        );
      },
    )
    );
  }

  Future _onChooseEp() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => _EpChooser(
        widget.struct.epNameMap,
        widget.struct.epOrder,
        widget.struct.onChangeEp,
      ),
    );
  }

  Future _onMoreSetting() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => _SettingPanel(
        widget.struct.onReloadEp,
      ),
    );
  }

  bool _fullscreenController() {
    return widget.fullScreenAction == FullScreenAction.controller;
  }

  Future _onNextAction() async {
    if (widget.struct.epNameMap.containsKey(widget.struct.epOrder + 1)) {
      widget.struct.onChangeEp(widget.struct.epOrder + 1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已经是最后一章了')),
      );
    }
  }

  bool _hasNextEp() =>
      widget.struct.epNameMap.containsKey(widget.struct.epOrder + 1);

  double _topBarHeight() => Scaffold.of(context).appBarMaxHeight ?? 0;

  double _bottomBarHeight() => 45;
}

///////////////////////////////////////////////////////////////////////////////
// Ep Chooser

class _EpChooser extends StatefulWidget {
  final Map<int, String> epNameMap;
  final int epOrder;
  final FutureOr Function(int) onChangeEp;

  const _EpChooser(this.epNameMap, this.epOrder, this.onChangeEp);

  @override
  State<StatefulWidget> createState() => _EpChooserState();
}

class _EpChooserState extends State<_EpChooser> {
  @override
  Widget build(BuildContext context) {
    var entries = widget.epNameMap.entries.toList();
    entries.sort((a, b) => a.key - b.key);
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      child: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final isCurrent = entry.key == widget.epOrder;
          return ListTile(
            title: Text(entry.value),
            trailing: isCurrent
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            selected: isCurrent,
            onTap: () {
              Navigator.pop(context);
              widget.onChangeEp(entry.key);
            },
          );
        },
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////
// Setting Panel

class _SettingPanel extends StatefulWidget {
  final FutureOr Function() onReloadEp;

  const _SettingPanel(this.onReloadEp);

  @override
  State<StatefulWidget> createState() => _SettingPanelState();
}

class _SettingPanelState extends State<_SettingPanel> {
  late ReaderMode _readerMode = ReaderMode.webtoon;
  late FullScreenAction _fullScreenAction = FullScreenAction.touchOnce;
  bool _noAnimation = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final modeStr = await loadAppSetting(key: 'reader_mode');
    final fullScreenStr = await loadAppSetting(key: 'full_screen_action');
    final noAniStr = await loadAppSetting(key: 'no_animation');

    setState(() {
      if (modeStr != null) {
        final index = int.tryParse(modeStr) ?? 0;
        if (index >= 0 && index < ReaderMode.values.length) {
          _readerMode = ReaderMode.values[index];
        }
      }
      if (fullScreenStr != null) {
        final index = int.tryParse(fullScreenStr) ?? 0;
        if (index >= 0 && index < FullScreenAction.values.length) {
          _fullScreenAction = FullScreenAction.values[index];
        }
      }
      if (noAniStr != null) {
        _noAnimation = noAniStr == '1' || noAniStr.toLowerCase() == 'true';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      child: ListView(
        children: [
          ListTile(
            title: const Text('阅读器模式'),
            subtitle: Text(_readerMode.displayName),
            onTap: () async {
              final result = await showDialog<ReaderMode>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('选择阅读器模式'),
                  children: ReaderMode.values.map((mode) {
                    return SimpleDialogOption(
                      child: ListTile(
                        leading: Icon(mode.icon),
                        title: Text(mode.displayName),
                        trailing: mode == _readerMode
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                      ),
                      onPressed: () => Navigator.pop(context, mode),
                    );
                  }).toList(),
                ),
              );
              if (result != null) {
                await saveAppSetting(key: 'reader_mode', value: result.index.toString());
                setState(() => _readerMode = result);
                widget.onReloadEp();
              }
            },
          ),
          ListTile(
            title: const Text('全屏操作模式'),
            subtitle: Text(_getFullScreenActionName(_fullScreenAction)),
            onTap: () async {
              final result = await showDialog<FullScreenAction>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('选择全屏操作模式'),
                  children: FullScreenAction.values.map((action) {
                    return SimpleDialogOption(
                      child: ListTile(
                        title: Text(_getFullScreenActionName(action)),
                        trailing: action == _fullScreenAction
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                      ),
                      onPressed: () => Navigator.pop(context, action),
                    );
                  }).toList(),
                ),
              );
              if (result != null) {
                await saveAppSetting(key: 'full_screen_action', value: result.index.toString());
                setState(() => _fullScreenAction = result);
                widget.onReloadEp();
              }
            },
          ),
          SwitchListTile(
            title: const Text('取消翻页动画'),
            subtitle: const Text('禁用列表/画廊翻页动画，直接跳转'),
            value: _noAnimation,
            onChanged: (v) async {
              setState(() => _noAnimation = v);
              await saveAppSetting(key: 'no_animation', value: v ? '1' : '0');
              widget.onReloadEp();
            },
          ),
        ],
      ),
    );
  }

  String _getFullScreenActionName(FullScreenAction action) {
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
}

///////////////////////////////////////////////////////////////////////////////
// WebToon Reader State

class _WebToonReaderState extends _ImageReaderContentState {
  var _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
  late final List<Size?> _trueSizes = [];
  late final ItemScrollController _itemScrollController;
  late final ItemPositionsListener _itemPositionsListener;

  @override
  void initState() {
    for (var e in widget.struct.images) {
      _trueSizes.add(null);
    }
    _itemScrollController = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onListCurrentChange);
    super.initState();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onListCurrentChange);
    super.dispose();
  }

  void _onListCurrentChange() {
    var positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      var to = positions.first.index;
      if (to >= 0 && to < widget.struct.images.length) {
        super._onCurrentChange(to);
      }
    }
  }

  @override
  void _needJumpTo(int index, bool animation) {
    final time = DateTime.now().millisecondsSinceEpoch;
    if (_controllerTime > time) {
      return;
    }
    _controllerTime = time + 400;

    final useAnimation = animation && !widget.noAnimation;
    if (useAnimation) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
      );
    } else {
      _itemScrollController.jumpTo(index: index);
    }
  }

  @override
  void _needScrollForward() {}

  @override
  void _needScrollBackward() {}

  @override
  Widget _buildViewer() {
    return Container(
      color: Colors.black,
      child: _buildList(),
    );
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return ScrollablePositionedList.builder(
          initialScrollIndex: super._startIndex,
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          itemCount: widget.struct.images.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (index >= widget.struct.images.length) {
              return _buildNextEp();
            }
            return _buildImage(index, width, height);
          },
        );
      },
    );
  }

  Widget _buildImage(int index, double width, double height) {
    final picture = widget.struct.images[index];
    // 确保尺寸值有效，防止 Matrix4 无限值错误
    final safeWidth = width.isFinite && width > 0 ? width : 100.0;
    final safeHeight = height.isFinite && height > 0 ? height : 100.0;
    return CachedImageWidget(
      imageInfo: picture.media,
      moduleId: widget.struct.moduleId,
      metadata: picture.metadata,
      fit: BoxFit.fitWidth,
      width: safeWidth,
      placeholder: Container(
        width: safeWidth,
        height: safeHeight / 2,
        color: Colors.grey[900],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorWidget: Container(
        width: safeWidth,
        height: safeHeight / 2,
        color: Colors.grey[900],
        child: const Icon(Icons.broken_image, size: 60, color: Colors.grey),
      ),
    );
  }

  Widget _buildNextEp() {
    if (super._fullscreenController()) {
      return Container();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Divider(),
          const Text('本章结束', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 20),
          if (_hasNextEp())
            ElevatedButton(
              onPressed: () => _onNextAction(),
              child: const Text('下一章'),
            )
          else
            const Text('已经是最后一章了'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////
// WebToon Zoom Reader State

class _WebToonZoomReaderState extends _WebToonReaderState {
  @override
  Widget _buildList() {
    return GestureZoomBox(child: super._buildList());
  }
}

///////////////////////////////////////////////////////////////////////////////
// ListView Reader State (Free Zoom)

class _ListViewReaderState extends _ImageReaderContentState
    with SingleTickerProviderStateMixin {
  final List<Size?> _trueSizes = [];
  final _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  late final _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );
  late final _scrollController = ScrollController();

  @override
  void initState() {
    for (var e in widget.struct.images) {
      _trueSizes.add(null);
    }
    super.initState();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void _needJumpTo(int index, bool animation) {}

  int _controllerTime = 0;

  @override
  void _needScrollForward() {
    var first = _scrollController.offset;
    var scrollSize = MediaQuery.of(context).size.height * 0.8;
    var pos = first + scrollSize;
    if (pos > _scrollController.position.maxScrollExtent) {
      pos = _scrollController.position.maxScrollExtent;
    }
    if (widget.noAnimation) {
      _scrollController.jumpTo(pos);
    } else {
      _scrollController.animateTo(
        pos,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
  }

  @override
  void _needScrollBackward() {
    var first = _scrollController.offset;
    var scrollSize = MediaQuery.of(context).size.height * 0.8;
    var pos = first - scrollSize;
    if (pos < 0) {
      pos = 0;
    }
    if (widget.noAnimation) {
      _scrollController.jumpTo(pos);
    } else {
      _scrollController.animateTo(
        pos,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
  }

  @override
  Widget _buildViewer() {
    return Container(
      color: Colors.black,
      child: _buildList(),
    );
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return GestureDetector(
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 4.0,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: widget.struct.images.length + 1,
              itemBuilder: (context, index) {
                if (index >= widget.struct.images.length) {
                  return _buildNextEp();
                }
                return _buildImage(index, constraints.maxWidth, constraints.maxHeight);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildImage(int index, double width, double height) {
    final picture = widget.struct.images[index];
    // 确保尺寸值有效，防止 Matrix4 无限值错误
    final safeWidth = width.isFinite && width > 0 ? width : 100.0;
    final safeHeight = height.isFinite && height > 0 ? height : 100.0;
    return CachedImageWidget(
      imageInfo: picture.media,
      moduleId: widget.struct.moduleId,
      metadata: picture.metadata,
      fit: BoxFit.fitWidth,
      width: safeWidth,
      placeholder: Container(
        width: safeWidth,
        height: safeHeight / 2,
        color: Colors.grey[900],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorWidget: Container(
        width: safeWidth,
        height: safeHeight / 2,
        color: Colors.grey[900],
        child: const Icon(Icons.broken_image, size: 60, color: Colors.grey),
      ),
    );
  }

  Widget _buildNextEp() {
    if (super._fullscreenController()) {
      return Container();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Divider(),
          const Text('本章结束', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 20),
          if (_hasNextEp())
            ElevatedButton(
              onPressed: () => _onNextAction(),
              child: const Text('下一章'),
            )
          else
            const Text('已经是最后一章了'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_animationController.isAnimating) {
      return;
    }
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final details = _doubleTapDetails;
      if (details != null) {
        final position = details.localPosition;
        if (position.dx.isFinite && position.dy.isFinite) {
          _transformationController.value = Matrix4.identity()
            ..translate(-position.dx, -position.dy)
            ..scale(2.0);
        }
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
// Gallery Reader State

class _GalleryReaderState extends _ImageReaderContentState {
  late PageController _pageController;
  final _cacheManager = ImageCacheManager();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: super._startIndex);
    _preloadJump(super._startIndex, init: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void _needJumpTo(int index, bool animation) {
    final useAnimation = animation && !widget.noAnimation;
    if (useAnimation) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    } else {
      _pageController.jumpToPage(index);
    }
    _preloadJump(index);
  }

  @override
  void _needScrollForward() {}

  @override
  void _needScrollBackward() {}

  _preloadJump(int index, {bool init = false}) {
    void fn() async {
      // 预加载当前和后续两张
      for (var i = index; i < index + 3 && i < widget.struct.images.length; i++) {
        final picture = widget.struct.images[i];
        final url = _composeUrl(picture);
        final params = _processParams(widget.struct.moduleId, picture);
        await _cacheManager.cacheImage(
          widget.struct.moduleId,
          url,
          headers: picture.media.headers,
          processParams: params,
        );
      }
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    } else {
      fn();
    }
  }

  void _onGalleryPageChange(int to) {
    // 预加载后续页面
    _preloadJump(to);
    if (to >= 0 && to < widget.struct.images.length) {
      super._onCurrentChange(to);
    }
  }

  @override
  Widget _buildViewer() {
    var gallery = PhotoViewGallery.builder(
      scrollDirection: widget.pagerDirection == ReaderDirection.topToBottom
          ? Axis.vertical
          : Axis.horizontal,
      reverse: widget.pagerDirection == ReaderDirection.rightToLeft,
      pageController: _pageController,
      itemCount: widget.struct.images.length,
      builder: (BuildContext context, int index) {
        final picture = widget.struct.images[index];
        return PhotoViewGalleryPageOptions.customChild(
          child: Center(
            child: CachedImageWidget(
              imageInfo: picture.media,
              moduleId: widget.struct.moduleId,
              metadata: picture.metadata,
              fit: BoxFit.contain,
            ),
          ),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        );
      },
      onPageChanged: _onGalleryPageChange,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    );

    return Stack(
      children: [
        gallery,
        _buildNextEpController(),
      ],
    );
  }

  String _composeUrl(Picture picture) {
    final info = picture.media;
    if (info.fileServer.isEmpty) return info.path;
    return '${info.fileServer}${info.path}';
  }

  Map<String, dynamic>? _processParams(String moduleId, Picture picture) {
    // 优先使用 metadata
    if (picture.metadata.isNotEmpty) {
      return picture.metadata.map((k, v) => MapEntry(k, v as dynamic));
    }
    // 针对 jasmine 的参数提取
    if (moduleId == 'jasmine') {
      try {
        final uri = Uri.parse(_composeUrl(picture));
        final segments = uri.pathSegments;
        final idx = segments.indexOf('photos');
        if (idx != -1 && idx + 2 < segments.length) {
          return {
            'chapterId': segments[idx + 1],
            'imageName': segments[idx + 2],
          };
        }
      } catch (_) {}
    }
    return null;
  }

  Widget _buildNextEpController() {
    if (super._fullscreenController() ||
        _current < widget.struct.images.length - 1) {
      return Container();
    }
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: _onNextAction,
            child: const Text('下一章'),
          ),
        ),
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////
// Two Page Gallery Reader State

class _TwoPageGalleryReaderState extends _ImageReaderContentState {
  late PageController _pageController;
  var _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
  late final List<Size?> _trueSizes = [];
  List<ImageProvider> ips = [];
  List<PhotoViewGalleryPageOptions> options = [];
  final _cacheManager = ImageCacheManager();

  @override
  void initState() {
    for (var e in widget.struct.images) {
      _trueSizes.add(null);
    }
    super.initState();
    _pageController = PageController(initialPage: super._startIndex ~/ 2);
    for (var index = 0; index < widget.struct.images.length; index++) {
      final picture = widget.struct.images[index];
      final url = getImageUrl(picture.media);
      ips.add(NetworkImage(url));
    }

    // 创建双页选项
    for (var index = 0; index < ips.length; index += 2) {
      if (index + 1 < ips.length) {
        // 双页
        options.add(
          PhotoViewGalleryPageOptions.customChild(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: PhotoView(
                    imageProvider: ips[index],
                    backgroundDecoration: const BoxDecoration(color: Colors.black),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                    tightMode: true,
                  ),
                ),
                Expanded(
                  child: PhotoView(
                    imageProvider: ips[index + 1],
                    backgroundDecoration: const BoxDecoration(color: Colors.black),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                    tightMode: true,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // 单页
        options.add(
          PhotoViewGalleryPageOptions(
            imageProvider: ips[index],
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
          ),
        );
      }
    }

    _preloadJump(super._startIndex, init: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void _needJumpTo(int index, bool animation) {
    final pageIndex = index ~/ 2;
    final useAnimation = animation && !widget.noAnimation;
    if (useAnimation) {
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    } else {
      _pageController.jumpToPage(pageIndex);
    }
    _preloadJump(index);
  }

  @override
  void _needScrollBackward() {}

  @override
  void _needScrollForward() {}

  _preloadJump(int index, {bool init = false}) {
    void fn() async {
      for (var i = index; i < index + 4 && i < widget.struct.images.length; i++) {
        final picture = widget.struct.images[i];
        final url = _composeUrl(picture);
        final params = _processParams(widget.struct.moduleId, picture);
        await _cacheManager.cacheImage(
          widget.struct.moduleId,
          url,
          headers: picture.media.headers,
          processParams: params,
        );
      }
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    } else {
      fn();
    }
  }

  @override
  Widget _buildViewer() {
    return Stack(
      children: [
        PhotoViewGallery(
          pageOptions: options,
          pageController: _pageController,
          onPageChanged: _onGalleryPageChange,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
        ),
        _buildNextEpController(),
      ],
    );
  }

  void _onGalleryPageChange(int to) {
    var toIndex = to * 2;
    _preloadJump(toIndex);
    if (to >= 0 && to < widget.struct.images.length) {
      super._onCurrentChange(toIndex);
    }
  }

  Widget _buildNextEpController() {
    if (super._fullscreenController() ||
        _current < widget.struct.images.length - 2) {
      return Container();
    }
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: _onNextAction,
            child: const Text('下一章'),
          ),
        ),
      ),
    );
  }

  String _composeUrl(Picture picture) {
    final info = picture.media;
    if (info.fileServer.isEmpty) return info.path;
    return '${info.fileServer}${info.path}';
  }

  Map<String, dynamic>? _processParams(String moduleId, Picture picture) {
    if (picture.metadata.isNotEmpty) {
      return picture.metadata.map((k, v) => MapEntry(k, v as dynamic));
    }
    if (moduleId == 'jasmine') {
      try {
        final uri = Uri.parse(_composeUrl(picture));
        final segments = uri.pathSegments;
        final idx = segments.indexOf('photos');
        if (idx != -1 && idx + 2 < segments.length) {
          return {
            'chapterId': segments[idx + 1],
            'imageName': segments[idx + 2],
          };
        }
      } catch (_) {}
    }
    return null;
  }
}
