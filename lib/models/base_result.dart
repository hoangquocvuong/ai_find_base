class BaseResult {
  final String id;
  final String slug;
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
    this.id = '',
    this.slug = '',
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
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      level: json['level']?.toString() ?? '',
      baseType: json['baseType']?.toString() ?? '',
      style: json['style']?.toString() ?? '',
      defense: json['defense']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      postUrl: json['postUrl']?.toString() ?? '',
      accessLink: json['accessLink']?.toString() ?? '',
      premium: json['premium'] == true,
      score: (json['score'] is num)
          ? (json['score'] as num).toDouble()
          : double.tryParse(json['score']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
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