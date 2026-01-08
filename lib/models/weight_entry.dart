/// Represents a weight measurement entry.
class WeightEntry {
  /// Unique identifier
  final String id;

  /// Weight in kilograms
  final double weight;

  /// When the weight was recorded
  final DateTime dateTime;

  WeightEntry({
    required this.id,
    required this.weight,
    required this.dateTime,
  });

  /// Creates a new weight entry with auto-generated ID
  factory WeightEntry.create({
    required double weight,
    DateTime? date,
  }) {
    final now = DateTime.now();
    final entryDate = date ?? now;
    return WeightEntry(
      id: now.millisecondsSinceEpoch.toString(),
      weight: weight,
      dateTime: entryDate,
    );
  }

  /// Converts to JSON for storage
  Map<String, dynamic> toJson() => {
        'id': id,
        'weight': weight,
        'dateTime': dateTime.toIso8601String(),
      };

  /// Creates from JSON
  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
        id: json['id'] as String,
        weight: (json['weight'] as num).toDouble(),
        dateTime: DateTime.parse(json['dateTime'] as String),
      );
}
