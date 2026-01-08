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
}
