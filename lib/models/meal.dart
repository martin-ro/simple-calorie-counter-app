import 'food_entry.dart';

/// Represents a saved meal (combination of foods).
class Meal {
  /// Unique identifier
  final String id;

  /// Meal name (e.g., "Morning Smoothie")
  final String name;

  /// List of food items in this meal
  final List<MealItem> items;

  /// Which meal types this meal is available for
  final List<MealType> mealTypes;

  /// Total calories (calculated from items)
  int get totalCalories => items.fold(0, (sum, item) => sum + item.calories);

  /// Total macros (calculated from items)
  double get totalFat => items.fold(0.0, (sum, item) => sum + item.fat);
  double get totalCarbs => items.fold(0.0, (sum, item) => sum + item.carbs);
  double get totalProtein => items.fold(0.0, (sum, item) => sum + item.protein);
  double get totalSugars => items.fold(0.0, (sum, item) => sum + item.sugars);

  Meal({
    required this.id,
    required this.name,
    required this.items,
    required this.mealTypes,
  });

  /// Creates a Meal from JSON
  factory Meal.fromJson(Map<String, dynamic> json) {
    return Meal(
      id: json['id'] as String,
      name: json['name'] as String,
      items: (json['items'] as List<dynamic>)
          .map((item) => MealItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      mealTypes: (json['mealTypes'] as List<dynamic>?)
          ?.map((t) => MealType.values.firstWhere((e) => e.name == t))
          .toList() ?? [MealType.breakfast, MealType.lunch, MealType.dinner, MealType.snacks],
    );
  }

  /// Converts to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items.map((item) => item.toJson()).toList(),
      'mealTypes': mealTypes.map((t) => t.name).toList(),
    };
  }
}

/// A single food item within a saved meal
class MealItem {
  final String name;
  final int calories;
  final double fat;
  final double carbs;
  final double protein;
  final double sugars;

  MealItem({
    required this.name,
    required this.calories,
    this.fat = 0,
    this.carbs = 0,
    this.protein = 0,
    this.sugars = 0,
  });

  factory MealItem.fromJson(Map<String, dynamic> json) {
    return MealItem(
      name: json['name'] as String,
      calories: json['calories'] as int,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      sugars: (json['sugars'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'calories': calories,
      'fat': fat,
      'carbs': carbs,
      'protein': protein,
      'sugars': sugars,
    };
  }
}
