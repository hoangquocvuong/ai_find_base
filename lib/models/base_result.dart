class BaseResult {
  final String title;
  final String level;
  final String baseType;
  final String style;
  final String defense;
  final String image;
  final String postUrl;
  final String accessLink;
  final bool premium;
  final double score;

  BaseResult({
    required this.title,
    required this.level,
    required this.baseType,
    required this.style,
    required this.defense,
    required this.image,
    required this.postUrl,
    required this.accessLink,
    required this.premium,
    required this.score,
  });

  factory BaseResult.fromJson(Map<String, dynamic> json) {
    return BaseResult(
      title: json['title'] ?? '',
      level: json['level'] ?? '',
      baseType: json['baseType'] ?? '',
      style: json['style'] ?? '',
      defense: json['defense'] ?? '',
      image: json['image'] ?? '',
      postUrl: json['postUrl'] ?? '',
      accessLink: json['accessLink'] ?? '',
      premium: json['premium'] == true,
      score: (json['score'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'level': level,
      'baseType': baseType,
      'style': style,
      'defense': defense,
      'image': image,
      'postUrl': postUrl,
      'accessLink': accessLink,
      'premium': premium,
      'score': score,
    };
  }
}