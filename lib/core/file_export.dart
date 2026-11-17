import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('io.github.yuuge7.companion/export');

/// Only the file-picker plumbing is shared. Each mode owns its serialization.
Future<String?> saveTextFile({
  required String fileName,
  required String content,
  String mimeType = 'application/octet-stream',
}) async {
  if (Platform.isAndroid) {
    return _channel.invokeMethod<String>('saveFile', {
      'fileName': fileName,
      'content': content,
      'mimeType': mimeType,
    });
  }
  final target = await getSaveLocation(suggestedName: fileName);
  if (target == null) return null;
  await XFile.fromData(
    Uint8List.fromList(utf8.encode(content)),
    mimeType: mimeType,
    name: fileName,
  ).saveTo(target.path);
  return target.path;
}
