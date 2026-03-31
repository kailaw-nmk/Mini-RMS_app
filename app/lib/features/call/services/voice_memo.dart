import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Offline voice memo recorder
/// Records audio when the driver is offline, auto-sends on reconnect
class VoiceMemoService {
  MediaRecorder? _recorder;
  String? _currentFilePath;
  bool _isRecording = false;
  final List<String> _pendingMemos = [];

  /// Whether a recording is in progress
  bool get isRecording => _isRecording;

  /// Number of pending (unsent) memos
  int get pendingCount => _pendingMemos.length;

  /// Start recording a voice memo
  Future<void> startRecording() async {
    if (_isRecording) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentFilePath = '${dir.path}/voice_memo_$timestamp.webm';

      _recorder = MediaRecorder();
      await _recorder!.start(_currentFilePath!);

      _isRecording = true;
      debugPrint('VoiceMemo: recording started -> $_currentFilePath');
    } catch (e) {
      debugPrint('VoiceMemo: failed to start recording: $e');
    }
  }

  /// Stop recording and save the memo
  Future<String?> stopRecording() async {
    if (!_isRecording || _recorder == null) return null;

    try {
      await _recorder!.stop();
      _isRecording = false;

      if (_currentFilePath != null) {
        _pendingMemos.add(_currentFilePath!);
        debugPrint(
            'VoiceMemo: saved, ${_pendingMemos.length} pending');
      }

      final path = _currentFilePath;
      _currentFilePath = null;
      _recorder = null;
      return path;
    } catch (e) {
      debugPrint('VoiceMemo: failed to stop recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Get all pending memo file paths for sending
  List<String> getPendingMemos() => List.unmodifiable(_pendingMemos);

  /// Mark a memo as sent (remove from pending list)
  void markAsSent(String filePath) {
    _pendingMemos.remove(filePath);
    debugPrint(
        'VoiceMemo: marked as sent, ${_pendingMemos.length} remaining');
  }

  /// Delete a sent memo file
  Future<void> deleteMemo(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      markAsSent(filePath);
    } catch (e) {
      debugPrint('VoiceMemo: failed to delete: $e');
    }
  }
}
