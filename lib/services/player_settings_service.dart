import 'package:shared_preferences/shared_preferences.dart';

/// 播放器设置持久化服务
///
/// 从 VideoPlayerController 中提取的纯设置 CRUD 方法，
/// 与播放器运行时状态无关。
class PlayerSettingsService {
  static const String _decodeModeKey = 'video_decode_mode';
  static const String _expandBufferKey = 'video_expand_buffer';
  static const String _audioOutputKey = 'video_audio_output';

  static Future<String> getDecodeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_decodeModeKey) ?? 'no';
  }

  static Future<void> setDecodeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_decodeModeKey, mode);
  }

  static Future<bool> getExpandBuffer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_expandBufferKey) ?? true;
  }

  static Future<void> setExpandBuffer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandBufferKey, value);
  }

  static Future<String> getAudioOutput() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_audioOutputKey) ?? 'audiotrack';
  }

  static Future<void> setAudioOutput(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_audioOutputKey, value);
  }

  static String getDecodeModeDisplayName(String mode) {
    switch (mode) {
      case 'no':
        return '软解码';
      case 'auto-copy':
        return '硬解码';
      default:
        return '软解码';
    }
  }

  static String getAudioOutputDisplayName(String value) {
    switch (value) {
      case 'audiotrack':
        return 'AudioTrack';
      case 'aaudio':
        return 'AAudio';
      case 'opensles':
        return 'OpenSL ES';
      default:
        return value;
    }
  }
}
