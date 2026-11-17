import 'dart:io';

Future<void> atomicWrite(File target, List<int> bytes) async {
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(target.path);
}
