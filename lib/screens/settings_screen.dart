import 'package:flutter/material.dart';
import 'package:comics/src/rust/api/init.dart';
import 'package:comics/components/image_cache_settings_tile.dart';
import 'package:comics/components/proxy_settings_tile.dart';

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
      children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('应用目录'),
            subtitle: FutureBuilder<String?>(
              future: Future.value(getRootPath()),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? '未初始化');
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('模块目录'),
            subtitle: FutureBuilder<String?>(
              future: Future.value(getModulesDir()),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? '未初始化');
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('缓存目录'),
            subtitle: FutureBuilder<String?>(
              future: Future.value(getCacheDir()),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? '未初始化');
              },
            ),
          ),
          const Divider(),
          // 图片缓存管理
          const ImageCacheSettingsTile(),
          const Divider(),
          // 代理设置
          const ProxySettingsTile(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            subtitle: const Text('Comics Browser v1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Comics Browser',
                applicationVersion: '1.0.0',
                applicationLegalese: '基于 Flutter + Rust 架构的多模块漫画浏览器',
              );
            },
          ),
        ],
      ),
    );
  }
}
