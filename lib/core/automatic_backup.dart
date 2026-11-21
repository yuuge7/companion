import 'dart:io';

import 'package:flutter/services.dart';

import 'atomic_file.dart';
import 'companion_backup.dart';
import 'companion_data.dart';

/// Native scheduling owns folder grants and retention. Dart always uses the same
/// serializer and validation as a manual complete backup, including cover files.
class AutomaticBackup {
  static const channel = MethodChannel('io.github.yuuge7.companion/backups');

  static Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('status') ?? {},
      );
  static Future<bool> chooseFolder() async =>
      await channel.invokeMethod<bool>('chooseFolder') ?? false;
  static Future<void> setFrequency(int hours) =>
      channel.invokeMethod('setFrequency', hours);
  static Future<void> disable() => channel.invokeMethod('disable');
  static Future<void> backupNow() => channel.invokeMethod('backupNow');

  static Future<void> prepare(CompanionData data, String path) async {
    final backup = CompanionBackup(data);
    final bytes = await backup.create();
    // Never publish an archive which the restore flow cannot read.
    backup.decode(bytes);
    await atomicWrite(File(path), bytes);
  }

  static void attach(CompanionData data) {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'prepare') throw MissingPluginException();
      await prepare(data, call.arguments as String);
      return true;
    });
  }

  static void detach() => channel.setMethodCallHandler(null);
}
