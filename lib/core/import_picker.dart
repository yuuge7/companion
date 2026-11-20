import 'package:flutter/widgets.dart';
import 'package:file_selector/file_selector.dart';

/// Download providers often label JSON as HTML, plain text or octet-stream.
/// Let the content parser validate the file rather than disabling it in Android.
Future<XFile?> pickLibraryImport() {
  FocusManager.instance.primaryFocus?.unfocus();
  return openFile();
}
