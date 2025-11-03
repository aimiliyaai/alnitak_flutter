import 'dart:convert';
import 'video_api_model.dart';

class ApiResponse {
  final int code;
  final VideoData? data;
  final String msg;

  ApiResponse({
    required this.code,
    this.data,
    required this.msg,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      code: json['code'] ?? 0,
      data: json['data'] != null ? VideoData.fromJson(json['data']) : null,
      msg: json['msg'] ?? '',
    );
  }

  bool get isSuccess => code == 200;
}

class VideoData {
  final List<VideoApiModel> videos;

  VideoData({
    required this.videos,
  });

  factory VideoData.fromJson(Map<String, dynamic> json) {
    return VideoData(
      videos: (json['videos'] as List<dynamic>?)
              ?.map((v) => VideoApiModel.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
