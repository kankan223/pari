import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/evidence_item.dart';
import '../domain/evidence_ports.dart';

/// Production [EvidencePicker] (data layer, Task 8.2) — wraps the
/// `file_picker` plugin. This is the SINGLE file in the War Room that
/// touches the platform file system; the picked bytes are handed straight
/// to the encryption pipeline and the raw [PickedEvidence.displayName] is
/// never persisted, queued, logged, or rendered.
class FilePickerEvidencePicker implements EvidencePicker {
  final FilePicker _picker;

  FilePickerEvidencePicker({FilePicker? picker})
      : _picker = picker ?? FilePicker.platform;

  @override
  Future<PickedEvidence?> pick() async {
    final result = await _picker.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) {
      return null; // cancelled
    }
    final bytes = file.bytes!;
    final name = file.name;
    return PickedEvidence(
      bytes: Uint8List.fromList(bytes),
      displayName: name,
      mimeType: _mimeFromName(name),
      sizeBytes: file.size,
    );
  }

  /// Coarse mime inference from the file extension — presentation metadata
  /// only (the sealed envelope never depends on it for integrity).
  static String _mimeFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return 'application/octet-stream';
    }
    final ext = name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'pdf' => 'application/pdf',
      'txt' || 'md' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }
}
