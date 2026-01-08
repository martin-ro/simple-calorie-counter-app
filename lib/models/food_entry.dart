/// Meal types for categorizing food entries
enum MealType { breakfast, lunch, dinner, snacks }

/// Represents a single food entry with name and calorie count.
///
/// This is the main data model for the calorie tracker app.
/// Each entry has a unique ID, the food name, calories, and when it was added.
class FoodEntry {
  /// Unique identifier for this entry (used for deletion)
  final String id;

  /// Name of the food (e.g., "Apple", "Chicken Salad")
  final String name;

  /// Number of calories
  final int calories;

  /// Macronutrients in grams
  final double fat;
  final double carbs;
  final double protein;
  final double sugars;

  /// When this entry was created
  final DateTime dateTime;

  /// Which meal this entry belongs to
  final MealType mealType;

  FoodEntry({
    required this.id,
    required this.name,
    required this.calories,
    this.fat = 0,
    this.carbs = 0,
    this.protein = 0,
    this.sugars = 0,
    required this.dateTime,
    required this.mealType,
  });

  /// Creates a new FoodEntry with an auto-generated ID.
  ///
  /// Use this factory when adding a new entry from user input.
  /// If [date] is provided, the entry will be created for that date (at current time).
  factory FoodEntry.create({
    required String name,
    required int calories,
    double fat = 0,
    double carbs = 0,
    double protein = 0,
    double sugars = 0,
    required MealType mealType,
    DateTime? date,
  }) {
    final now = DateTime.now();
    final entryDate = date != null
        ? DateTime(date.year, date.month, date.day, now.hour, now.minute, now.second)
        : now;
    return FoodEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      calories: calories,
      fat: fat,
      carbs: carbs,
      protein: protein,
      sugars: sugars,
      dateTime: entryDate,
      mealType: mealType,
    );
  }

  /// Converts this entry to a JSON map for storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'calories': calories,
      'fat': fat,
      'carbs': carbs,
      'protein': protein,
      'sugars': sugars,
      'dateTime': dateTime.toIso8601String(),
      'mealType': mealType.name,
    };
  }

  /// Creates a FoodEntry from a JSON map (loaded from storage).
  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    return FoodEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      calories: json['calories'] as int,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      sugars: (json['sugars'] as num?)?.toDouble() ?? 0,
      dateTime: DateTime.parse(json['dateTime'] as String),
      mealType: MealType.values.firstWhere(
        (e) => e.name == json['mealType'],
        orElse: () => MealType.snacks,
      ),
    );
  }
}
