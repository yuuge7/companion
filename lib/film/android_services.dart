import 'package:flutter/services.dart';

import 'diagnostics.dart';

abstract final class AndroidServices {
  static const channel = MethodChannel('dev.ionel.movie_companion/device');
  static Future<Map<String, dynamic>> backupStatus() async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('backupStatus') ?? {},
      );
  static Future<bool> chooseBackupFolder() async =>
      await channel.invokeMethod<bool>('chooseBackupFolder') ?? false;
  static Future<void> disableBackup() => channel.invokeMethod('disableBackup');
  static Future<void> backupNow() => channel.invokeMethod('backupNow');
  static Future<void> refreshWidget() async {
    try {
      await channel.invokeMethod('refreshWidget');
    } on MissingPluginException {
      return;
    } catch (error, stack) {
      Diagnostics.record(error, stack, source: 'widget refresh');
    }
  }

  static Future<void> pinWidget() => channel.invokeMethod('pinWidget');
}
