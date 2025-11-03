import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// 日志服务类，用于记录错误和调试信息到文件
class LoggerService {
  static LoggerService? _instance;
  static LoggerService get instance {
    _instance ??= LoggerService._();
    return _instance!;
  }

  LoggerService._();

  File? _logFile;
  static const String _logFileName = 'error_log.txt';
  static const int _maxLogFileSize = 10 * 1024 * 1024; // 10MB

  /// 初始化日志服务
  Future<void> initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File('${directory.path}/$_logFileName');
      
      // 如果文件过大，清空或归档
      if (await _logFile!.exists()) {
        final fileSize = await _logFile!.length();
        if (fileSize > _maxLogFileSize) {
          await _archiveOldLogs();
        }
      }
    } catch (e) {
      print('❌ 初始化日志服务失败: $e');
    }
  }

  /// 归档旧日志
  Future<void> _archiveOldLogs() async {
    try {
      if (_logFile == null || !await _logFile!.exists()) return;

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final archiveFile = File('${directory.path}/logs/error_log_$timestamp.txt');
      
      // 创建logs目录
      final logsDir = Directory('${directory.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // 移动旧日志
      await _logFile!.copy(archiveFile.path);
      await _logFile!.delete();
      
      print('📦 旧日志已归档: ${archiveFile.path}');
    } catch (e) {
      print('❌ 归档日志失败: $e');
    }
  }

  /// 写入日志到文件
  Future<void> _writeToFile(String message) async {
    if (_logFile == null) {
      await initialize();
    }

    try {
      if (_logFile == null) return;

      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      final logEntry = '[$timestamp] $message\n\n';
      
      // 追加写入文件
      await _logFile!.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      print('❌ 写入日志文件失败: $e');
    }
  }

  /// 记录错误日志
  Future<void> logError({
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('❌ ERROR: $message');
    
    if (error != null) {
      buffer.writeln('Error: $error');
    }
    
    if (stackTrace != null) {
      buffer.writeln('StackTrace:');
      buffer.writeln(stackTrace.toString());
    }
    
    if (context != null && context.isNotEmpty) {
      buffer.writeln('Context:');
      context.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
    }
    
    buffer.writeln('─' * 80);

    // 控制台输出
    print(buffer.toString());
    
    // 写入文件
    await _writeToFile(buffer.toString());
  }

  /// 记录API错误日志
  Future<void> logApiError({
    required String apiName,
    required String url,
    int? statusCode,
    String? responseBody,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? requestParams,
  }) async {
    final context = <String, dynamic>{
      'API名称': apiName,
      '请求URL': url,
      if (statusCode != null) 'HTTP状态码': statusCode,
      if (responseBody != null) '响应体': responseBody.length > 1000 
          ? '${responseBody.substring(0, 1000)}... (截断)' 
          : responseBody,
      if (requestParams != null) '请求参数': requestParams,
    };

    await logError(
      message: 'API请求失败: $apiName',
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// 记录数据加载错误
  Future<void> logDataLoadError({
    required String dataType,
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    final fullContext = <String, dynamic>{
      '数据类型': dataType,
      '操作': operation,
      if (context != null) ...context,
    };

    await logError(
      message: '数据加载失败: $dataType - $operation',
      error: error,
      stackTrace: stackTrace,
      context: fullContext,
    );
  }

  /// 记录调试信息（仅控制台输出，不写入文件）
  void logDebug(String message) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    print('[$timestamp] 🔍 DEBUG: $message');
  }

  /// 记录信息（控制台输出）
  void logInfo(String message) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    print('[$timestamp] ℹ️ INFO: $message');
  }

  /// 获取日志文件路径
  Future<String?> getLogFilePath() async {
    if (_logFile == null) {
      await initialize();
    }
    return _logFile?.path;
  }

  /// 读取日志内容
  Future<String?> readLogs({int? maxLines}) async {
    if (_logFile == null || !await _logFile!.exists()) {
      return null;
    }

    try {
      final content = await _logFile!.readAsString();
      if (maxLines != null) {
        final lines = content.split('\n');
        if (lines.length > maxLines) {
          return lines.sublist(lines.length - maxLines).join('\n');
        }
      }
      return content;
    } catch (e) {
      print('❌ 读取日志失败: $e');
      return null;
    }
  }

  /// 清空日志
  Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
      await initialize();
      logInfo('日志已清空');
    }
  }
}
