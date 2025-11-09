import 'package:flutter/material.dart';
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

    final captchaData = await _captchaService.getCaptcha(widget.captchaId);

    if (captchaData != null) {
      setState(() {
        _captchaData = captchaData;
        _isLoading = false;
      });
    } else {
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

    final success = await _captchaService.validateCaptcha(
      captchaId: widget.captchaId,
      x: x,
    );

    if (success) {
      widget.onSuccess();
      if (mounted) {
        Navigator.pop(context);
      }
    } else {
      setState(() {
        _errorMessage = '验证失败，请重新滑动';
        _sliderPosition = 0;
        _isValidating = false;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '安全验证',
                    style: TextStyle(
                      fontSize: 18,
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
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建验证码区域
  Widget _buildCaptchaArea() {
    return Column(
      children: [
        // 背景图和滑块
        Stack(
          children: [
            // 背景图
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _decodeBase64(_captchaData!.bgImg),
                fit: BoxFit.cover,
              ),
            ),
            // 滑块
            Positioned(
              left: _sliderPosition,
              top: _captchaData!.y.toDouble(),
              child: Image.memory(
                _decodeBase64(_captchaData!.sliderImg),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 滑动条
        Container(
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
                          .clamp(0.0, MediaQuery.of(context).size.width - 100);
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isValidating) return;

                    // 验证位置
                    final x = _sliderPosition.round();
                    _validateSlider(x);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
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
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.chevron_right, color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
