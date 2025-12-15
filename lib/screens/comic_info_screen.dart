import 'package:flutter/material.dart';
import 'package:comics/src/rust/api/module_api.dart';
import 'package:comics/src/rust/modules/types.dart';
import 'package:comics/src/cached_image_widget.dart';
import 'package:comics/src/history_manager.dart';
import 'comic_reader_screen.dart';
import 'package:comics/src/reader_progress.dart';

/// 漫画详情页面
class ComicInfoScreen extends StatefulWidget {
  final String moduleId;
  final String moduleName;
  final String comicId;
  final String comicTitle;

  const ComicInfoScreen({
    super.key,
    required this.moduleId,
    required this.moduleName,
    required this.comicId,
    required this.comicTitle,
  });

  @override
  State<ComicInfoScreen> createState() => _ComicInfoScreenState();
}

class _ComicInfoScreenState extends State<ComicInfoScreen> {
  ComicDetail? _comicDetail;
  List<Ep> _eps = [];
  bool _loadingDetail = true;
  bool _loadingEps = true;
  String? _detailError;
  String? _epsError;
  int _tabIndex = 0;
  Ep? _resumeEp;
  int? _resumePosition;

  @override
  void initState() {
    super.initState();
    _loadComicDetail();
    _loadEps();
  }

  Future<void> _loadComicDetail() async {
    setState(() {
      _loadingDetail = true;
      _detailError = null;
    });

    try {
      final detail = await getComicDetail(
        moduleId: widget.moduleId,
        comicId: widget.comicId,
      );
      setState(() {
        _comicDetail = detail;
        _loadingDetail = false;
      });

      // 记录历史（不阻塞 UI）
      HistoryManager.instance
          .recordVisit(
            moduleId: widget.moduleId,
            moduleName: widget.moduleName,
            comicId: widget.comicId,
            comicTitle: detail.title,
            thumb: detail.thumb,
          )
          .catchError((e) {
        debugPrint('Failed to record history: $e');
      });
    } catch (e) {
      setState(() {
        _detailError = e.toString();
        _loadingDetail = false;
      });
    }
  }

  Future<void> _loadEps() async {
    setState(() {
      _loadingEps = true;
      _epsError = null;
    });

    try {
      List<Ep> allEps = [];
      int page = 1;
      int totalPages = 1;

      do {
        final epPage = await getEps(
          moduleId: widget.moduleId,
          comicId: widget.comicId,
          page: page,
        );
        allEps.addAll(epPage.docs);
        totalPages = epPage.pageInfo.pages;
        page++;
      } while (page <= totalPages);

      setState(() {
        _eps = allEps;
        _loadingEps = false;
      });

      // 读取继续阅读位置（选择最后一个有进度的章节）
      _loadResumeProgress();
    } catch (e) {
      setState(() {
        _epsError = e.toString();
        _loadingEps = false;
      });
    }
  }

  Future<void> _loadResumeProgress() async {
    Ep? lastWithProgress;
    int? lastPos;
    for (final ep in _eps) {
      final pos = await ReaderProgressManager.getProgress(
        moduleId: widget.moduleId,
        comicId: widget.comicId,
        epId: ep.id,
      );
      if (pos != null) {
        lastWithProgress = ep; // 持续覆盖，取列表中的最后一个
        lastPos = pos;
      }
    }
    if (mounted) {
      setState(() {
        _resumeEp = lastWithProgress;
        _resumePosition = lastPos;
      });
    }
  }

  void _openReader(Ep ep) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicReaderScreen(
          moduleId: widget.moduleId,
          comicId: widget.comicId,
          comicTitle: _comicDetail?.title ?? widget.comicTitle,
          epList: _eps,
          currentEp: ep,
        ),
      ),
    );
  }

  void _openTag(String tag) {
    // TODO: 实现标签搜索
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('搜索标签: $tag')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_comicDetail?.title ?? widget.comicTitle),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingDetail) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_detailError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadComicDetail,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('错误详情', style: TextStyle(fontSize: 14)),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.all(8),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _detailError!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final comic = _comicDetail!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 漫画信息卡片
          _buildInfoCard(comic),
          // 标签
          if (comic.tags.isNotEmpty) _buildTags(comic),
          // 描述
          if (comic.description.isNotEmpty) _buildDescription(comic),
          // 更新信息
          _buildUpdateInfo(comic),
          // Tab 切换
          Container(
            height: 48,
            color: theme.colorScheme.secondary.withValues(alpha: 0.05),
            child: Row(
              children: [
                _buildTabButton('章节 (${comic.epsCount})', 0),
                _buildTabButton('详情', 1),
              ],
            ),
          ),
          // Tab 内容
          _tabIndex == 0 ? _buildEpsList() : _buildDetailInfo(comic),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ComicDetail comic) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedImageWidget(
              imageInfo: comic.thumb,
              moduleId: widget.moduleId,
              width: 120,
              height: 160,
              fit: BoxFit.cover,
              placeholder: Container(
                width: 120,
                height: 160,
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: Container(
                width: 120,
                height: 160,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, size: 40),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comic.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (comic.author.isNotEmpty)
                  _buildInfoRow(Icons.person, comic.author),
                if (comic.chineseTeam.isNotEmpty)
                  _buildInfoRow(Icons.group, comic.chineseTeam),
                _buildInfoRow(
                  Icons.category,
                  comic.categories.join(' / '),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStat(Icons.remove_red_eye, '${comic.viewsCount}'),
                    const SizedBox(width: 16),
                    _buildStat(Icons.favorite, '${comic.likesCount}'),
                    const SizedBox(width: 16),
                    if (comic.finished)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
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
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTags(ComicDetail comic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: comic.tags.map((tag) {
          return InkWell(
            onTap: () => _openTag(tag),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDescription(ComicDetail comic) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '简介',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            comic.description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateInfo(ComicDetail comic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (comic.updatedAt.isNotEmpty)
            Text(
              '更新于: ${comic.updatedAt}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          if (comic.createdAt.isNotEmpty)
            Text(
              '创建于: ${comic.createdAt}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final isSelected = _tabIndex == index;
    final theme = Theme.of(context);
    
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? theme.colorScheme.primary : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpsList() {
    if (_loadingEps) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_epsError != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              '加载章节失败',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadEps,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('错误详情', style: TextStyle(fontSize: 14)),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.all(8),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    _epsError!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_eps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('暂无章节')),
      );
    }

    // 开始/继续阅读按钮
    return Column(
      children: [
        // 继续阅读按钮（如果有进度）
        if (_resumeEp != null && _resumePosition != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openReaderWithResume(_resumeEp!, _resumePosition!),
                icon: const Icon(Icons.history),
                label: Text('继续阅读 · ${_resumeEp!.title}'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        // 开始阅读按钮
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openReader(_eps.first),
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始阅读'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        // 章节列表
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _eps.map((ep) {
              return InkWell(
                onTap: () => _openReader(ep),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    ep.title,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _openReaderWithResume(Ep ep, int position) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicReaderScreen(
          moduleId: widget.moduleId,
          comicId: widget.comicId,
          comicTitle: _comicDetail?.title ?? widget.comicTitle,
          epList: _eps,
          currentEp: ep,
          initPosition: position,
        ),
      ),
    );
  }

  Widget _buildDetailInfo(ComicDetail comic) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('漫画ID', comic.id),
          _buildDetailRow('作者', comic.author),
          _buildDetailRow('汉化组', comic.chineseTeam),
          _buildDetailRow('分类', comic.categories.join(', ')),
          _buildDetailRow('总页数', '${comic.pagesCount}'),
          _buildDetailRow('章节数', '${comic.epsCount}'),
          _buildDetailRow('观看数', '${comic.viewsCount}'),
          _buildDetailRow('点赞数', '${comic.likesCount}'),
          _buildDetailRow('评论数', '${comic.commentsCount}'),
          _buildDetailRow('允许下载', comic.allowDownload ? '是' : '否'),
          _buildDetailRow('状态', comic.finished ? '已完结' : '连载中'),
          _buildDetailRow('更新时间', comic.updatedAt),
          _buildDetailRow('创建时间', comic.createdAt),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
