import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/carousel_model.dart';
import '../services/carousel_service.dart';
import '../utils/image_utils.dart';
import '../theme/theme_extensions.dart';
import 'cached_image_widget.dart';

/// 首页轮播图组件
class CarouselWidget extends StatefulWidget {
  final int partitionId;
  final Function(CarouselItem item)? onTap;

  const CarouselWidget({
    super.key,
    this.partitionId = 0,
    this.onTap,
  });

  @override
  State<CarouselWidget> createState() => _CarouselWidgetState();
}

class _CarouselWidgetState extends State<CarouselWidget> {
  final CarouselService _carouselService = CarouselService();
  late PageController _pageController;

  List<CarouselItem> _carouselList = [];
  int _currentIndex = 0;
  int _realIndex = 0; // 真实页面索引（用于无限循环）
  Timer? _autoPlayTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCarousel();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadCarousel() async {
    final list = await _carouselService.getCarousel(partitionId: widget.partitionId);
    if (mounted) {
      _preloadImages(list);
      setState(() {
        _carouselList = list;
        _isLoading = false;
      });
      if (list.isNotEmpty) {
        // 初始化PageController，起始位置在中间（用于无限循环）
        _pageController = PageController(initialPage: list.length * 100);
        _realIndex = list.length * 100;
        if (list.length > 1) {
          _startAutoPlay();
        }
      } else {
        _pageController = PageController();
      }
    }
  }

  void _preloadImages(List<CarouselItem> items) {
    for (final item in items) {
      SmartCacheManager.preloadImage(
        ImageUtils.getFullImageUrl(item.img),
        cacheKey: 'carousel_${item.id}',
      );
    }
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_carouselList.length <= 1) return;
      // 始终向右滑动（向左动画效果）
      _realIndex++;
      _pageController.animateToPage(
        _realIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  void _onPageChanged(int index) {
    _realIndex = index;
    setState(() {
      _currentIndex = index % _carouselList.length;
    });
  }

  void _goToPage(int targetIndex) {
    // 计算需要移动的距离，始终向前（向左）移动
    final currentMod = _realIndex % _carouselList.length;
    int delta = targetIndex - currentMod;
    if (delta <= 0) {
      delta += _carouselList.length; // 保证始终向前
    }
    _realIndex += delta;
    _pageController.animateToPage(
      _realIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildPlaceholder();
    }

    if (_carouselList.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onPanDown: (_) => _stopAutoPlay(),
      onPanCancel: () => _startAutoPlay(),
      onPanEnd: (_) => _startAutoPlay(),
      child: Container(
height: 220.h,
margin: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        child: ClipRRect(
borderRadius: BorderRadius.circular(12.r),
          child: Stack(
            children: [
              // 轮播图内容（无限循环）
              PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: null, // 无限循环
                itemBuilder: (context, index) {
                  final realIndex = index % _carouselList.length;
                  return _buildCarouselItem(_carouselList[realIndex]);
                },
              ),
              // 底部渐变遮罩和标题
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomOverlay(),
              ),
              // 指示器
              Positioned(
                right: 12,
                bottom: 12,
                child: _buildIndicators(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    final colors = context.colors;
    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.skeleton,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildCarouselItem(CarouselItem item) {
    return GestureDetector(
      onTap: () => widget.onTap?.call(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 图片
          CachedImage(
            imageUrl: ImageUtils.getFullImageUrl(item.img),
            fit: BoxFit.cover,
            cacheKey: 'carousel_${item.id}',
          ),
          // 颜色遮罩（底部渐变）
          if (item.color.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 80.h,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      _parseColor(item.color).withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomOverlay() {
    if (_carouselList.isEmpty) return const SizedBox.shrink();

    final currentItem = _carouselList[_currentIndex];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 24, 60, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Text(
        currentItem.title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14.sp,
          fontWeight: FontWeight.w500,
          shadows: [
            Shadow(
              offset: Offset(0, 1),
              blurRadius: 2,
              color: Colors.black45,
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildIndicators() {
    if (_carouselList.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_carouselList.length, (index) {
        final isActive = index == _currentIndex;
        return GestureDetector(
          onTap: () => _goToPage(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 16.w : 6.w,
            height: 6.h,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3.r),
            ),
          ),
        );
      }),
    );
  }

  /// 解析颜色字符串
  Color _parseColor(String colorStr) {
    try {
      // 支持 #RRGGBB 或 RRGGBB 格式
      String hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (e) {
      // 解析失败返回黑色
    }
    return Colors.black;
  }
}
