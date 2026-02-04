import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../models/captcha_models.dart';
import '../services/captcha_service.dart';

/// 滑块验证组件
class SliderCaptchaWidget extends StatefulWidget {
  final String captchaId;
  final VoidCallback onSuccess;
  final VoidCallback? onCancel;

  const SliderCaptchaWidget({
    super.key,
    required this.captchaId,
    required this.onSuccess,
    this.onCancel,
  });

  @override
  State<SliderCaptchaWidget> createState() => _SliderCaptchaWidgetState();
}

class _SliderCaptchaWidgetState extends State<SliderCaptchaWidget> {
  final CaptchaService _captchaService = CaptchaService();

  CaptchaData? _captchaData;
  bool _isLoading = true;
  bool _isValidating = false;
  double _sliderPosition = 0;
  String? _errorMessage;

  // 缓存解码后的图片数据,避免每次setState都重新解码
  Uint8List? _cachedBgImage;
  Uint8List? _cachedSliderImage;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  /// 加载验证码
  Future<void> _loadCaptcha() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    print('🔍 开始加载验证码，captchaId: ${widget.captchaId}');
    final captchaData = await _captchaService.getCaptcha(widget.captchaId);

    if (captchaData != null) {
      print('✅ 验证码加载成功');
      print('   - y坐标: ${captchaData.y}');
      print('   - bgImg长度: ${captchaData.bgImg.length}');
      print('   - sliderImg长度: ${captchaData.sliderImg.length}');
      print('   - bgImg前缀: ${captchaData.bgImg.substring(0, captchaData.bgImg.length > 50 ? 50 : captchaData.bgImg.length)}');

      // 预先解码图片并缓存,避免每次setState都重新解码
      _cachedBgImage = _decodeBase64(captchaData.bgImg);
      _cachedSliderImage = _decodeBase64(captchaData.sliderImg);

      setState(() {
        _captchaData = captchaData;
        _isLoading = false;
      });
    } else {
      print('❌ 验证码加载失败');
      setState(() {
        _errorMessage = '加载验证码失败，请重试';
        _isLoading = false;
      });
    }
  }

  /// 验证滑块
  Future<void> _validateSlider(int x) async {
    if (_isValidating) return;

    setState(() => _isValidating = true);

    print('🔍 开始验证滑块位置');
    print('   - captchaId: ${widget.captchaId}');
    print('   - 提交的x坐标(原始坐标系): $x');
    print('   - 服务端y坐标(原始坐标系): ${_captchaData?.y}');
    print('   - 当前缩放比例: $_currentScale');
    print('   - 滑块UI位置(缩放后): $_sliderPosition');

    final success = await _captchaService.validateCaptcha(
      captchaId: widget.captchaId,
      x: x,
    );

    if (success) {
      print('✅ 滑块验证成功！');
      print('   - 提交的x坐标: $x (原始坐标系)');
      print('   - 对应的缩放后位置: ${x * _currentScale}');
      widget.onSuccess();
      if (mounted) {
        Navigator.pop(context);
      }
    } else {
      print('❌ 滑块验证失败！');
      print('   - 提交的x坐标: $x (原始坐标系)');
      print('   - 滑块UI位置: $_sliderPosition (缩放后)');
      print('   - 转换关系: $_sliderPosition / $_currentScale = ${_sliderPosition / _currentScale}');
      print('   - 服务端期望的x范围: 可能在 ${(_captchaData?.y ?? 0) - 5} ~ ${(_captchaData?.y ?? 0) + 5} 附近');
      setState(() {
        _errorMessage = '验证失败，请重新滑动';
        _sliderPosition = 0;
        _isValidating = false;
        // 清除缓存的图片
        _cachedBgImage = null;
        _cachedSliderImage = null;
      });
      // 重新加载验证码
      await Future.delayed(const Duration(seconds: 1));
      _loadCaptcha();
    }
  }

  /// Base64转图片
  Uint8List _decodeBase64(String base64String) {
    // 移除可能的data:image前缀
    final cleanBase64 = base64String.replaceAll(RegExp(r'data:image/[^;]+;base64,'), '');
    return base64Decode(cleanBase64);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              children: [
                Expanded(
                  child: Text(
                    '安全验证',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    widget.onCancel?.call();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 验证区域
            if (_isLoading)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loadCaptcha,
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_captchaData != null)
              _buildCaptchaArea(),

            const SizedBox(height: 16),

            // 提示文字
            Text(
              '拖动滑块完成拼图',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 当前缩放比例（用于验证时转换坐标）
  double _currentScale = 1.0;

  /// 构建验证码区域
  Widget _buildCaptchaArea() {
    return Column(
      children: [
        // 背景图和滑块
        Container(
          constraints: const BoxConstraints(maxWidth: 360),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 原始验证码图片尺寸 (与PC端一致)
              const originalWidth = 310.0;
              const originalHeight = 160.0;

              // 计算缩放比例
              final containerWidth = constraints.maxWidth;
              final scale = containerWidth / originalWidth;
              final scaledHeight = originalHeight * scale;

              // 保存当前缩放比例，用于验证时转换坐标
              _currentScale = scale;

              // 根据缩放比例调整y坐标
              final scaledY = _captchaData!.y.toDouble() * scale;

              // 滑块图片的原始尺寸（根据PC端实现，滑块为50×50px）
              const originalSliderWidth = 50.0;
              const originalSliderHeight = 50.0;

              // 计算缩放后的滑块尺寸
              final scaledSliderWidth = originalSliderWidth * scale;
              final scaledSliderHeight = originalSliderHeight * scale;

              print('📐 验证码缩放信息:');
              print('   - 原始尺寸: ${originalWidth}x$originalHeight');
              print('   - 容器宽度: $containerWidth');
              print('   - 缩放比例: $scale');
              print('   - 缩放后高度: $scaledHeight');
              print('   - 原始y坐标: ${_captchaData!.y}');
              print('   - 缩放后y坐标: $scaledY');
              print('   - 滑块原始尺寸: ${originalSliderWidth}x$originalSliderHeight');
              print('   - 滑块缩放尺寸: ${scaledSliderWidth}x$scaledSliderHeight');

              return ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: SizedBox(
                  width: containerWidth,
                  height: scaledHeight,
                  child: Stack(
                    children: [
                      // 背景图 - 使用 RepaintBoundary 隔离重绘
                      RepaintBoundary(
                        child: _cachedBgImage != null
                            ? Image.memory(
                                _cachedBgImage!,
                                width: containerWidth,
                                height: scaledHeight,
                                fit: BoxFit.fill, // 填充指定尺寸
                                gaplessPlayback: true, // 防止图片闪烁
                                errorBuilder: (context, error, stackTrace) {
                                  print('❌ 背景图加载失败: $error');
                                  return Container(
                                    height: scaledHeight,
                                    color: Colors.grey[300],
                                    child: const Center(child: Text('图片加载失败')),
                                  );
                                },
                              )
                            : Container(
                                height: scaledHeight,
                                color: Colors.grey[300],
                              ),
                      ),
                      // 滑块 - 只在位置改变时更新，同时缩放尺寸
                      Positioned(
                        left: _sliderPosition,
                        top: scaledY, // 使用缩放后的y坐标
                        child: _cachedSliderImage != null
                            ? Image.memory(
                                _cachedSliderImage!,
                                width: scaledSliderWidth, // 缩放宽度
                                height: scaledSliderHeight, // 缩放高度
                                fit: BoxFit.fill, // 填充指定尺寸
                                gaplessPlayback: true, // 防止图片闪烁
                                errorBuilder: (context, error, stackTrace) {
                                  print('❌ 滑块图加载失败: $error');
                                  return Container(
                                    width: scaledSliderWidth,
                                    height: scaledSliderHeight,
                                    color: Colors.red.withAlpha(128),
                                  );
                                },
                              )
                            : Container(
                                width: scaledSliderWidth,
                                height: scaledSliderHeight,
                                color: Colors.transparent,
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // 滑动条
        Container(
          constraints: const BoxConstraints(maxWidth: 360),
          child: LayoutBuilder(
            builder: (context, sliderConstraints) {
              final maxSliderWidth = sliderConstraints.maxWidth - 50; // 50是滑块按钮宽度

              return Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Stack(
                  children: [
                    // 滑动进度背景
                    if (_sliderPosition > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: _sliderPosition + 50,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                      ),
                    // 滑块按钮
                    Positioned(
                      left: _sliderPosition,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          if (_isValidating) return;

                          setState(() {
                            _sliderPosition = (_sliderPosition + details.delta.dx)
                                .clamp(0.0, maxSliderWidth);
                          });
                        },
                        onHorizontalDragEnd: (details) {
                          if (_isValidating) return;

                          // 验证位置 - 需要将缩放后的坐标转换回原始坐标系
                          final scaledX = _sliderPosition;
                          final originalX = (scaledX / _currentScale).round();

                          print('🖱️ 用户拖动结束:');
                          print('   - 滑块位置(缩放后像素): $scaledX');
                          print('   - 当前缩放比例: $_currentScale');
                          print('   - 转换回原始坐标: $originalX');
                          print('   - 原始y坐标: ${_captchaData?.y}');

                          _validateSlider(originalX);
                        },
                        child: Container(
                          width: 50.w,
height: 50.h,
                          decoration: BoxDecoration(
                            color: _isValidating ? Colors.grey : Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _isValidating
                              ? Center(
                                  child: SizedBox(
width: 20.w,
                height: 20.h,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : const Icon(Icons.chevron_right, color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
