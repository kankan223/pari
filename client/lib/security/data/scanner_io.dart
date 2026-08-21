import 'dart:io';
import 'dart:math';

List<dynamic> dartFilesIn(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

String readFileAsString(dynamic file) {
  if (file is File) return file.readAsStringSync();
  return '';
}

String generateUuid() {
  final random = Random.secure();
  final values = List<int>.generate(16, (_) => random.nextInt(256));
  values[6] = (values[6] & 0x0f) | 0x40;
  values[8] = (values[8] & 0x3f) | 0x80;
  return '${_hex(values.sublist(0, 4))}-'
      '${_hex(values.sublist(4, 6))}-'
      '${_hex(values.sublist(6, 8))}-'
      '${_hex(values.sublist(8, 10))}-'
      '${_hex(values.sublist(10, 16))}';
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
