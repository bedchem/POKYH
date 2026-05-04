class Dish {
  final String id;
  final Map<String, String> nameMap;
  final Map<String, String> descriptionMap;
  final String imageUrl;
  final String category;
  final List<String> tags;
  final int prepTime;
  final int calories;
  final double price;
  final double protein;
  final double fat;
  final List<String> allergens;
  final bool isVegetarian;
  final bool isVegan;
  final double rating;
  final DateTime date;

  const Dish({
    required this.id,
    required this.nameMap,
    this.descriptionMap = const {},
    this.imageUrl = '',
    this.category = '',
    this.tags = const [],
    this.prepTime = 0,
    this.calories = 0,
    this.price = 0,
    this.protein = 0,
    this.fat = 0,
    this.allergens = const [],
    this.isVegetarian = false,
    this.isVegan = false,
    this.rating = 0,
    required this.date,
  });

  /// Name in der aktuellen Sprache (Fallback: de -> erster Wert)
  String name([String lang = 'de']) =>
      nameMap[lang] ?? nameMap['de'] ?? nameMap.values.first;

  /// Beschreibung in der aktuellen Sprache
  String description([String lang = 'de']) =>
      descriptionMap[lang] ?? descriptionMap['de'] ?? '';

  bool get hasImage => imageUrl.isNotEmpty;
  bool hasDescription([String lang = 'de']) => description(lang).isNotEmpty;
  bool get hasCategory => category.isNotEmpty;
  bool get hasNutrition => calories > 0 || prepTime > 0 || price > 0 || protein > 0 || fat > 0;

  factory Dish.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String? ?? '';

    // name kann String oder Map sein
    final nameMap = _parseLocalized(json['name']);
    final descriptionMap = _parseLocalized(json['description']);

    final isVegetarian = json['isVegetarian'] as bool? ??
        category.toLowerCase().contains('vegetarisch') ||
            category.toLowerCase().contains('vegan');
    final isVegan = json['isVegan'] as bool? ??
        category.toLowerCase().contains('vegan');

    final defaultName = nameMap['de'] ?? nameMap.values.firstOrNull ?? '';

    return Dish(
      id: json['id'] as String? ?? defaultName.hashCode.toString(),
      nameMap: nameMap,
      descriptionMap: descriptionMap,
      imageUrl: json['imageUrl'] as String? ?? '',
      category: category,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : _autoTags(category),
      prepTime: json['prepTime'] as int? ?? 0,
      calories: json['calories'] as int? ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      allergens: json['allergens'] != null
          ? List<String>.from(json['allergens'] as List)
          : const [],
      isVegetarian: isVegetarian,
      isVegan: isVegan,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      date: json['date'] != null
          ? (DateTime.tryParse(json['date'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  /// Parst einen Wert der entweder ein String oder eine Map ist
  static Map<String, String> _parseLocalized(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    if (value is String) {
      return {'de': value, 'en': value, 'it': value};
    }
    return {'de': '', 'en': '', 'it': ''};
  }

  static List<String> _autoTags(String category) {
    if (category.isEmpty) return const [];
    final tags = <String>[category];
    final lower = category.toLowerCase();
    if (lower.contains('fisch')) tags.add('Fisch');
    if (lower.contains('vegan')) tags.add('Vegan');
    if (lower.contains('vegetarisch')) tags.add('Vegetarisch');
    return tags;
  }

  Dish copyWith({String? id, DateTime? date}) {
    return Dish(
      id: id ?? this.id,
      nameMap: nameMap,
      descriptionMap: descriptionMap,
      imageUrl: imageUrl,
      category: category,
      tags: tags,
      prepTime: prepTime,
      calories: calories,
      price: price,
      protein: protein,
      fat: fat,
      allergens: allergens,
      isVegetarian: isVegetarian,
      isVegan: isVegan,
      rating: rating,
      date: date ?? this.date,
    );
  }

  /// Flexible parser — handles whatever the backend returns:
  ///   array:                    [{...}, ...]
  ///   { dishes: [...] }
  ///   { data: [...] }
  ///   { menu: { dishes: [...] } }
  static List<Dish> listFromJsonDynamic(dynamic decoded) {
    List? raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic>) {
      raw = decoded['dishes'] as List? ??
          decoded['data'] as List? ??
          (decoded['menu'] as Map?)?['dishes'] as List?;
    }
    if (raw == null) return const [];
    final result = <Dish>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try {
          result.add(Dish.fromJson(item));
        } catch (_) {}
      }
    }
    return result;
  }

  static List<Dish> listFromJson(Map<String, dynamic> json) =>
      listFromJsonDynamic(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Dish && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
