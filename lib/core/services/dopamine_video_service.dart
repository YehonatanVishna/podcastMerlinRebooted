import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/app_settings.dart';

/// Service responsible for picking, importing, copying, and deleting
/// user-uploaded Dopamine Mode custom video files.
class DopamineVideoService {
  final FilePickerPlatform _filePicker;

  DopamineVideoService({FilePickerPlatform? filePicker})
      : _filePicker = filePicker ?? FilePickerPlatform.instance;

  /// Gets the dedicated app documents directory where imported dopamine videos are stored.
  static Future<Directory> getStorageDirectory() async {
    final appDocs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDocs.path, 'dopamine_videos'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Opens the native file picker to choose a video file, copies it into
  /// the app's persistent storage, and returns a [DopamineCustomVideo] record.
  /// Returns `null` if the user cancels or an error occurs.
  Future<DopamineCustomVideo?> pickAndImportVideo({
    FilePickerPlatform? customPicker,
  }) async {
    try {
      final picker = customPicker ?? _filePicker;
      final result = await picker.pickFiles(
        dialogTitle: 'Select Video for Dopamine Mode',
        type: FileType.video,
      );

      if (result.isEmpty) {
        return null;
      }

      final pickedFile = result.first;
      final sourcePath = pickedFile.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        debugPrint('[DopamineVideoService] Picked file has no path');
        return null;
      }

      final sourceIoFile = File(sourcePath);
      if (!await sourceIoFile.exists()) {
        debugPrint('[DopamineVideoService] Source file does not exist: $sourcePath');
        return null;
      }

      final storageDir = await getStorageDirectory();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final originalName = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : p.basename(sourcePath);

      // Sanitize filename to prevent directory traversal or invalid characters
      final sanitizedName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final targetPath = p.join(storageDir.path, '${id}_$sanitizedName');
      final targetIoFile = File(targetPath);

      // Copy source file to persistent app storage
      await sourceIoFile.copy(targetIoFile.path);
      final sizeBytes = await targetIoFile.length();

      // Display name without trailing extension for clean UI
      final displayName = p.basenameWithoutExtension(originalName);

      return DopamineCustomVideo(
        id: id,
        name: displayName,
        path: targetIoFile.path,
        sizeBytes: sizeBytes,
        addedAt: DateTime.now(),
      );
    } catch (e, stack) {
      debugPrint('[DopamineVideoService] Error importing video: $e\n$stack');
      return null;
    }
  }

  /// Deletes a custom video file from disk.
  Future<void> deleteVideo(DopamineCustomVideo video) async {
    try {
      final file = File(video.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[DopamineVideoService] Error deleting video file ${video.path}: $e');
    }
  }

  /// Removes any orphaned video files in the storage folder not in the registered list.
  Future<void> cleanupOrphanedFiles(List<DopamineCustomVideo> registeredVideos) async {
    try {
      final storageDir = await getStorageDirectory();
      final registeredPaths = registeredVideos.map((v) => p.normalize(v.path)).toSet();
      if (await storageDir.exists()) {
        await for (final entity in storageDir.list()) {
          if (entity is File && !registeredPaths.contains(p.normalize(entity.path))) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('[DopamineVideoService] Error cleaning up orphaned videos: $e');
    }
  }
}
