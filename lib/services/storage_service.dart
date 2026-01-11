import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/food_entry.dart';
import '../models/meal.dart';
import '../models/weight_entry.dart';

/// Handles saving and loading data to/from Firebase Firestore.
///
/// Data structure:
/// - users/{userId}/profile - user profile data
/// - users/{userId}/entries/{entryId} - food entries
/// - users/{userId}/meals/{mealId} - saved meals
class StorageService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Gets the current user's ID, or null if not logged in.
  String? get _userId => _auth.currentUser?.uid;

  /// Reference to the current user's document.
  DocumentReference? get _userDoc {
    final uid = _userId;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  /// Reference to the current user's entries collection.
  CollectionReference? get _entriesCollection {
    return _userDoc?.collection('entries');
  }

  /// Reference to the current user's meals collection.
  CollectionReference? get _mealsCollection {
    return _userDoc?.collection('meals');
  }

  /// Reference to the current user's weights collection.
  CollectionReference? get _weightsCollection {
    return _userDoc?.collection('weights');
  }

  /// Reference to the current user's exercise data collection.
  CollectionReference? get _exerciseCollection {
    return _userDoc?.collection('exercise');
  }

  /// Saves a single food entry to Firestore.
  Future<void> saveEntry(FoodEntry entry) async {
    final collection = _entriesCollection;
    if (collection == null) return;

    await collection.doc(entry.id).set(entry.toJson());
  }

  /// Saves all food entries to Firestore.
  Future<void> saveEntries(List<FoodEntry> entries) async {
    final collection = _entriesCollection;
    if (collection == null) return;

    final batch = _db.batch();
    for (final entry in entries) {
      batch.set(collection.doc(entry.id), entry.toJson());
    }
    await batch.commit();
  }

  /// Loads all food entries from Firestore.
  Future<List<FoodEntry>> loadEntries() async {
    final collection = _entriesCollection;
    if (collection == null) return [];

    final snapshot = await collection.orderBy('dateTime', descending: true).get();
    return snapshot.docs
        .map((doc) => FoodEntry.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Deletes a food entry from Firestore.
  Future<void> deleteEntry(String id) async {
    final collection = _entriesCollection;
    if (collection == null) return;

    await collection.doc(id).delete();
  }

  /// Saves user profile data to Firestore.
  Future<void> saveProfile(Map<String, dynamic> profile) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({'profile': profile}, SetOptions(merge: true));
  }

  /// Loads user profile data from Firestore.
  Future<Map<String, dynamic>?> loadProfile() async {
    final doc = _userDoc;
    if (doc == null) return null;

    final snapshot = await doc.get();
    if (!snapshot.exists) return null;

    final data = snapshot.data() as Map<String, dynamic>?;
    return data?['profile'] as Map<String, dynamic>?;
  }

  /// Saves a meal to Firestore.
  Future<void> saveMeal(Meal meal) async {
    final collection = _mealsCollection;
    if (collection == null) return;

    await collection.doc(meal.id).set(meal.toJson());
  }

  /// Loads all saved meals from Firestore.
  Future<List<Meal>> loadMeals() async {
    final collection = _mealsCollection;
    if (collection == null) return [];

    final snapshot = await collection.orderBy('name').get();
    return snapshot.docs
        .map((doc) => Meal.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Deletes a meal from Firestore.
  Future<void> deleteMeal(String id) async {
    final collection = _mealsCollection;
    if (collection == null) return;

    await collection.doc(id).delete();
  }

  /// Saves a weight entry to Firestore.
  Future<void> saveWeight(WeightEntry entry) async {
    final collection = _weightsCollection;
    if (collection == null) return;

    await collection.doc(entry.id).set(entry.toJson());
  }

  /// Loads all weight entries from Firestore.
  Future<List<WeightEntry>> loadWeights() async {
    final collection = _weightsCollection;
    if (collection == null) return [];

    final snapshot =
        await collection.orderBy('dateTime', descending: true).get();
    return snapshot.docs
        .map((doc) => WeightEntry.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Deletes a weight entry from Firestore.
  Future<void> deleteWeight(String id) async {
    final collection = _weightsCollection;
    if (collection == null) return;

    await collection.doc(id).delete();
  }

  // ==================== Exercise Data ====================

  /// Formats a date as YYYY-MM-DD for use as document ID.
  String _dateToId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Saves exercise data for a specific date.
  Future<void> saveExerciseData({
    required DateTime date,
    required int activeCalories,
    required int basalCalories,
  }) async {
    final collection = _exerciseCollection;
    if (collection == null) return;

    final docId = _dateToId(date);
    await collection.doc(docId).set({
      'date': date.toIso8601String(),
      'activeCalories': activeCalories,
      'basalCalories': basalCalories,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  /// Saves multiple exercise data entries in a batch.
  Future<void> saveExerciseDataBatch(List<Map<String, dynamic>> entries) async {
    final collection = _exerciseCollection;
    if (collection == null) return;

    final batch = _db.batch();
    for (final entry in entries) {
      final date = DateTime.parse(entry['date'] as String);
      final docId = _dateToId(date);
      batch.set(collection.doc(docId), {
        ...entry,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit();
  }

  /// Loads all exercise data from Firestore.
  Future<Map<String, Map<String, dynamic>>> loadAllExerciseData() async {
    final collection = _exerciseCollection;
    if (collection == null) return {};

    final snapshot = await collection.get();
    final result = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      result[doc.id] = doc.data() as Map<String, dynamic>;
    }
    return result;
  }

  /// Gets exercise data for a specific date.
  Future<Map<String, dynamic>?> getExerciseForDate(DateTime date) async {
    final collection = _exerciseCollection;
    if (collection == null) return null;

    final docId = _dateToId(date);
    final doc = await collection.doc(docId).get();
    if (!doc.exists) return null;
    return doc.data() as Map<String, dynamic>?;
  }

  /// Gets the dates that have exercise data stored.
  Future<Set<String>> getExerciseDates() async {
    final collection = _exerciseCollection;
    if (collection == null) return {};

    final snapshot = await collection.get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  // ==================== Budget History ====================

  /// Reference to the current user's budget history collection.
  CollectionReference? get _budgetHistoryCollection {
    return _userDoc?.collection('budgetHistory');
  }

  /// Saves a budget entry effective from today.
  Future<void> saveBudget(int calories) async {
    final collection = _budgetHistoryCollection;
    if (collection == null) return;

    final dateKey = _dateToId(DateTime.now());
    await collection.doc(dateKey).set({
      'calorieBudget': calories,
      'effectiveDate': dateKey,
    });
  }

  /// Loads all budget history entries.
  Future<List<Map<String, dynamic>>> loadBudgetHistory() async {
    final collection = _budgetHistoryCollection;
    if (collection == null) return [];

    final snapshot = await collection.orderBy('effectiveDate', descending: true).get();
    return snapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();
  }
}
