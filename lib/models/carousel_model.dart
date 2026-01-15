/// 轮播图数据模型
class CarouselItem {
  final int id;
  final String img;       // 图片路径
  final String title;     // 标题
  final String? url;      // 跳转链接（可选）
  final String color;     // 遮罩颜色
  final String createdAt;

  CarouselItem({
    required this.id,
    required this.img,
    required this.title,
    this.url,
    required this.color,
    required this.createdAt,
  });

  factory CarouselItem.fromJson(Map<String, dynamic> json) {
    return CarouselItem(
      id: json['id'] ?? 0,
      img: json['img'] ?? '',
      title: json['title'] ?? '',
      url: json['url'],
      color: json['color'] ?? '',
      createdAt: json['createdAt'] ?? '',
    );
  }
}
