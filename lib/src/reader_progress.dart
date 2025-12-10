import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 存储每个 [moduleId, comicId, epId] 的阅读进度
class ReaderProgressManager {
  static const String _storageKey = 'reader_progress_v1';

  /// 保存进度
  static Future<void> setProgress({
    required String moduleId,
    required String comicId,
    required String epId,
    required int position,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final map = raw == null ? <String, dynamic>{} : (jsonDecode(raw) as Map<String, dynamic>);
    final k = _key(moduleId, comicId, epId);
    map[k] = position;
    await prefs.setString(_storageKey, jsonEncode(map));
  }

  /// 读取进度, 若不存在返回 null
  static Future<int?> getProgress({
    required String moduleId,
    required String comicId,
    required String epId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final k = _key(moduleId, comicId, epId);
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
    } catch (_) {}
    return null;
  }

  /// 清除某一章节的进度
  static Future<void> clearProgress({
    required String moduleId,
    required String comicId,
    required String epId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final k = _key(moduleId, comicId, epId);
      map.remove(k);
      await prefs.setString(_storageKey, jsonEncode(map));
    } catch (_) {}
  }

  static String _key(String moduleId, String comicId, String epId) => '$moduleId::$comicId::$epId';
}
