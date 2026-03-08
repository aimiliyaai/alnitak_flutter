import 'package:flutter/material.dart';

/// 视频/合集状态码对应的文案与颜色（与后端 constant.go 一致）
/// - 0: AUDIT_APPROVED 审核通过（已发布）
/// - 100: CREATED_VIDEO 创建视频
/// - 200: VIDEO_PROCESSING 视频转码中
/// - 300: SUBMIT_REVIEW 提交审核中
/// - 500: WAITING_REVIEW 等待审核
/// - 2000: REVIEW_FAILED 审核不通过
/// - 3000: PROCESSING_FAIL 处理失败
class VideoStatusUtils {
  VideoStatusUtils._();

  /// 状态文案；0/已发布 返回空字符串（便于用 .isNotEmpty 判断是否展示）
  static String getStatusText(int? status) {
    if (status == null) return '';
    switch (status) {
      case 100:
      case 200:
      case 300:
        return '转码中';
      case 500:
        return '待审核';
      case 2000:
        return '审核不通过';
      case 3000:
        return '处理失败';
      case 0:
      default:
        return '';
    }
  }

  /// 状态颜色
  static Color getStatusColor(int? status) {
    if (status == null) return Colors.green;
    switch (status) {
      case 100:
      case 200:
      case 300:
        return Colors.orange;
      case 500:
        return Colors.blue;
      case 2000:
      case 3000:
        return Colors.red;
      case 0:
      default:
        return Colors.green;
    }
  }
}
