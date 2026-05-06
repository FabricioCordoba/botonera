import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/sound.dart';

class ImportedAudioFile {
  const ImportedAudioFile({
    required this.name,
    required this.source,
  });

  final String name;
  final String source;
}

class FileStorage {
  Future<Directory> _soundsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'custom_sounds'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _backgroundAssetsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'background_assets'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<ImportedAudioFile?> importAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
        withData: kIsWeb,
      );

      final file = result?.files.single;
      if (file == null) {
        return null;
      }

      if (kIsWeb) {
        if (file.bytes == null) {
          return null;
        }

        return ImportedAudioFile(
          name: file.name,
          source: Uri.dataFromBytes(
            file.bytes!,
            mimeType: _mimeTypeForExtension(
              p.extension(file.name).replaceFirst('.', '').toLowerCase(),
            ),
          ).toString(),
        );
      }

      final path = file.path;
      if (path == null) {
        return null;
      }

      final sourceFile = File(path);
      if (!await sourceFile.exists()) {
        return null;
      }

      final targetDir = await _soundsDirectory();
      final targetPath = p.join(
        targetDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(path)}',
      );

      final copied = await sourceFile.copy(targetPath);
      return ImportedAudioFile(
        name: p.basename(path),
        source: copied.path,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> reserveRecordingPath(String fileName) async {
    final dir = await _soundsDirectory();
    return p.join(dir.path, fileName);
  }

  Future<String> ensurePlayableFilePath(Sound sound) async {
    if (kIsWeb) {
      return sound.source;
    }

    if (!sound.isAsset) {
      return sound.source;
    }

    final targetDir = await _backgroundAssetsDirectory();
    final targetPath = p.join(targetDir.path, p.basename(sound.source));
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      return targetFile.path;
    }

    final data = await rootBundle.load(sound.source);
    await targetFile.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return targetFile.path;
  }

  Future<void> deleteIfExists(String filePath) async {
    if (kIsWeb || filePath.startsWith('data:') || filePath.startsWith('blob:')) {
      return;
    }

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int> computeStorageBytes(Iterable<String> filePaths) async {
    var bytes = 0;
    for (final filePath in filePaths) {
      if (filePath.startsWith('data:')) {
        try {
          bytes += Uri.parse(filePath).data?.contentAsBytes().length ?? 0;
        } catch (_) {}
        continue;
      }

      if (filePath.startsWith('blob:') || kIsWeb) {
        continue;
      }

      final file = File(filePath);
      if (await file.exists()) {
        bytes += await file.length();
      }
    }
    return bytes;
  }

  String _mimeTypeForExtension(String extension) {
    switch (extension) {
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'mp3':
      default:
        return 'audio/mpeg';
    }
  }
}
