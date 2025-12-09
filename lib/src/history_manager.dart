import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comics/src/rust/modules/types.dart';

/// 管理跨源的漫画浏览历史
class HistoryManager {
  HistoryManager._();

  static final HistoryManager instance = HistoryManager._();

  static const String _storageKey = 'reading_history_v1';
  static const int _maxEntries = 200;

  Future<void> recordVisit({
    required String moduleId,
    required String moduleName,
    required String comicId,
    required String comicTitle,
    RemoteImageInfo? thumb,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await loadHistory();

    final newEntry = HistoryEntry(
      moduleId: moduleId,
      moduleName: moduleName,
      comicId: comicId,
      comicTitle: comicTitle,
      thumb: thumb,
      visitedAt: DateTime.now(),
    );

    // 先移除同一漫画，保持唯一
    entries.removeWhere(
      (e) => e.moduleId == moduleId && e.comicId == comicId,
    );
    entries.insert(0, newEntry);

    // 裁剪长度
    final limited = entries.take(_maxEntries).toList();
    final encoded = limited.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, encoded);
  }

  Future<List<HistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey);
    if (rawList == null) return [];

    final entries = <HistoryEntry>[];
    for (final raw in rawList) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final entry = HistoryEntry.fromJson(map);
        if (entry != null) {
          entries.add(entry);
        }
      } catch (_) {
        // 忽略坏数据
      }
    }

    entries.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    return entries;
  }

  Future<void> removeByModule(String moduleId) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await loadHistory();
    final filtered = entries.where((e) => e.moduleId != moduleId).toList();
    final encoded = filtered.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, encoded);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

class HistoryEntry {
  final String moduleId;
  final String moduleName;
  final String comicId;
  final String comicTitle;
  final RemoteImageInfo? thumb;
  final DateTime visitedAt;

  const HistoryEntry({
    required this.moduleId,
    required this.moduleName,
    required this.comicId,
    required this.comicTitle,
    required this.thumb,
    required this.visitedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'moduleId': moduleId,
      'moduleName': moduleName,
      'comicId': comicId,
      'comicTitle': comicTitle,
      'thumb': thumb == null ? null : _thumbToJson(thumb!),
      'visitedAt': visitedAt.toIso8601String(),
    };
  }

  static HistoryEntry? fromJson(Map<String, dynamic> json) {
    final visited = DateTime.tryParse(json['visitedAt'] as String? ?? '');
    if (visited == null) return null;

    return HistoryEntry(
      moduleId: json['moduleId'] as String? ?? '',
      moduleName: json['moduleName'] as String? ?? '',
      comicId: json['comicId'] as String? ?? '',
      comicTitle: json['comicTitle'] as String? ?? '',
      thumb: _thumbFromJson(json['thumb']),
      visitedAt: visited,
    );
  }

  static Map<String, dynamic> _thumbToJson(RemoteImageInfo thumb) {
    return {
      'originalName': thumb.originalName,
      'path': thumb.path,
      'fileServer': thumb.fileServer,
      'headers': thumb.headers,
    };
  }

  static RemoteImageInfo? _thumbFromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final headers = <String, String>{};
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key is String && value is String) {
          headers[key] = value;
        }
      });
    }

    final originalName = json['originalName'] as String?;
    final path = json['path'] as String?;
    final fileServer = json['fileServer'] as String?;
    if (originalName == null || path == null || fileServer == null) {
      return null;
    }

    return RemoteImageInfo(
      originalName: originalName,
      path: path,
      fileServer: fileServer,
      headers: headers,
    );
  }
}
