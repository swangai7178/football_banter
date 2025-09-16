class BanterItem {
  final String title;
  final String description;

  BanterItem({required this.title, required this.description});

  factory BanterItem.fromJson(Map<String, dynamic> json) {
    return BanterItem(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
    );
  }
}
