import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  final String name;
  final String version;
  final String buildNumber;

  static AppInfo? _data;

  const AppInfo({
    this.name = 'Not initialized',
    this.version = 'Not initialized',
    this.buildNumber = 'Not initialized',
  });

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final packageInfo = await PackageInfo.fromPlatform();
    AppInfo._data = AppInfo(
      name: packageInfo.appName,
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
    );
  }

  static AppInfo get data {
    if (_data == null) {
      throw StateError('AppInfo is not initialized');
    }
    return _data!;
  }

  String get versionInfo {
    var parts = <String>[];
    if (version.isNotEmpty) {
      parts.add('version $version');
    }
    if (buildNumber.isNotEmpty) {
      parts.add('(build $buildNumber)');
    }

    return parts.join(' ');
  }

  @override
  String toString() => '$name $versionInfo';
}
