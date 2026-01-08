/// Represents a food item from the OpenFoodFacts database.
///
/// This is different from FoodEntry - Food is a search result that the user
/// can select, while FoodEntry is what gets logged to their food diary.
class Food {
  /// Barcode (EAN/UPC)
  final String id;

  /// Product name
  final String name;

  /// Brand name
  final String? brand;

  /// Calories per 100g
  final double calories100g;

  /// Macros per 100g
  final double fat100g;
  final double carbs100g;
  final double protein100g;
  final double sugars100g;

  /// Serving size description (e.g., "1 can (330ml)")
  final String? servingSize;

  /// Serving size in grams
  final double? servingGrams;

  /// Calories per serving
  final double? caloriesPerServing;

  /// Macros per serving
  final double? fatPerServing;
  final double? carbsPerServing;
  final double? proteinPerServing;
  final double? sugarsPerServing;

  /// Product categories
  final List<String>? categories;

  Food({
    required this.id,
    required this.name,
    this.brand,
    required this.calories100g,
    required this.fat100g,
    required this.carbs100g,
    required this.protein100g,
    required this.sugars100g,
    this.servingSize,
    this.servingGrams,
    this.caloriesPerServing,
    this.fatPerServing,
    this.carbsPerServing,
    this.proteinPerServing,
    this.sugarsPerServing,
    this.categories,
  });

  /// Creates a Food from Meilisearch search result
  factory Food.fromJson(Map<String, dynamic> json) {
    return Food(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unknown',
      brand: json['brand'] as String?,
      calories100g: _parseDouble(json['calories_100g']) ?? 0,
      fat100g: _parseDouble(json['fat_100g']) ?? 0,
      carbs100g: _parseDouble(json['carbs_100g']) ?? 0,
      protein100g: _parseDouble(json['protein_100g']) ?? 0,
      sugars100g: _parseDouble(json['sugars_100g']) ?? 0,
      servingSize: json['serving_size'] as String?,
      servingGrams: _parseDouble(json['serving_grams']),
      caloriesPerServing: _parseDouble(json['calories_serving']),
      fatPerServing: _parseDouble(json['fat_serving']),
      carbsPerServing: _parseDouble(json['carbs_serving']),
      proteinPerServing: _parseDouble(json['protein_serving']),
      sugarsPerServing: _parseDouble(json['sugars_serving']),
      categories: (json['categories'] as List<dynamic>?)
          ?.map((c) => c.toString())
          .toList(),
    );
  }

  /// Helper to parse a value that could be num or String to double
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Display name including brand if available
  String get displayName {
    if (brand != null && brand!.isNotEmpty) {
      return '$name ($brand)';
    }
    return name;
  }
}
