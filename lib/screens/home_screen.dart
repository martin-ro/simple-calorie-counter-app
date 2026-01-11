import 'dart:math';

import 'package:flutter/material.dart';

import '../models/food_entry.dart';
import '../models/meal.dart';
import '../models/weight_entry.dart';
import '../services/auth_service.dart';
import '../services/health_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_card.dart';
import 'add_food_screen.dart';
import 'calories_detail_screen.dart';
import 'settings_screen.dart';

/// The main screen of the calorie tracker app.
///
/// Displays:
/// - Today's total calories at the top
/// - A list of food entries for today
/// - A floating action button to add new entries
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // All food entries (not just today's - we store everything)
  List<FoodEntry> _entries = [];

  // User's calorie budget from profile (default/fallback)
  int _calorieBudget = 2000; // Default fallback

  // Budget history (sorted by effectiveDate descending)
  List<Map<String, dynamic>> _budgetHistory = [];

  // Meal budgets (value and isPercent for each meal)
  Map<String, Map<String, dynamic>> _mealBudgets = {};

  // Service for saving/loading data
  final StorageService _storage = StorageService();

  // Service for authentication
  final AuthService _authService = AuthService();

  // Service for health data (Health Connect / HealthKit)
  final HealthService _healthService = HealthService();

  // Exercise calories burned (from health data)
  int _exerciseCalories = 0;

  // Cached exercise data from Firestore (keyed by YYYY-MM-DD)
  Map<String, Map<String, dynamic>> _exerciseCache = {};

  // Whether we've already synced historical health data this session
  bool _hasInitialSynced = false;

  // Loading state for initial data load
  bool _isLoading = true;

  // Current bottom nav tab (0 = Dashboard, 1 = Log)
  int _currentTab = 1; // Start on Log tab

  // Selected date for viewing entries
  DateTime _selectedDate = DateTime.now();

  // Scroll controller for log tab
  final ScrollController _scrollController = ScrollController();
  bool _showFloatingBar = false;

  // Week start preference ('monday' or 'sunday')
  String _weekStartDay = 'monday';

  // Unit preference (true = metric/kg, false = imperial/lb)
  bool _useMetric = true;

  // Target/goal weight (in kg)
  double? _targetWeight;

  // Weight entries
  List<WeightEntry> _weights = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Show floating bar when scrolled past the calorie card (~200px)
    final shouldShow = _scrollController.offset > 180;
    if (shouldShow != _showFloatingBar) {
      setState(() {
        _showFloatingBar = shouldShow;
      });
    }
  }

  /// Loads entries and profile from local storage when the app starts
  Future<void> _loadData() async {
    final entries = await _storage.loadEntries();
    final profile = await _storage.loadProfile();
    final weights = await _storage.loadWeights();
    final budgetHistory = await _storage.loadBudgetHistory();

    // Load health data if permissions granted
    await _loadHealthData();

    setState(() {
      _entries = entries;
      _weights = weights;
      _budgetHistory = budgetHistory;
      if (profile != null && profile['calorieBudget'] != null) {
        _calorieBudget = profile['calorieBudget'] as int;
      }
      // Load meal budgets
      if (profile != null && profile['mealBudgets'] != null) {
        _mealBudgets = Map<String, Map<String, dynamic>>.from(
          (profile['mealBudgets'] as Map).map(
            (key, value) => MapEntry(key as String, Map<String, dynamic>.from(value as Map)),
          ),
        );
      }
      _weekStartDay = profile?['weekStart'] as String? ?? 'monday';
      _useMetric = profile?['useMetric'] as bool? ?? true;
      // Load target weight (convert to kg if stored in lb)
      final targetWeight = profile?['targetWeight'] as num?;
      final weightUnit = profile?['weightUnit'] as String?;
      if (targetWeight != null) {
        _targetWeight = weightUnit == 'lb'
            ? targetWeight.toDouble() / 2.20462
            : targetWeight.toDouble();
      }
      _isLoading = false;
    });
  }

  /// Loads exercise calorie data from Firestore cache or Health Connect
  Future<void> _loadHealthData() async {
    final hasPermissions = await _healthService.hasPermissions();
    if (!hasPermissions) {
      setState(() {
        _exerciseCalories = 0;
      });
      return;
    }

    // Load cached data from Firestore
    if (_exerciseCache.isEmpty) {
      _exerciseCache = await _storage.loadAllExerciseData();
    }

    // Get exercise data for selected date from cache
    final dateId = _dateToId(_selectedDate);
    final cached = _exerciseCache[dateId];
    if (cached != null) {
      setState(() {
        _exerciseCalories = cached['activeCalories'] as int? ?? 0;
      });
    } else {
      setState(() {
        _exerciseCalories = 0;
      });
    }

    // Sync historical data in background on first load only
    if (!_hasInitialSynced) {
      _hasInitialSynced = true;
      _syncHistoricalHealthData();
    }
  }

  /// Handles pull-to-refresh - syncs health data from Health Connect
  Future<void> _onRefresh() async {
    final hasPermissions = await _healthService.hasPermissions();
    if (!hasPermissions) return;

    // Sync today's data from Health Connect
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final newData = await _healthService.syncHistoricalData(
      startDate: startOfDay,
      existingDates: {}, // Empty set to force refresh
    );

    if (newData.isNotEmpty) {
      // Save to Firestore
      final batch = newData
          .map((data) => {
                'date': data.date.toIso8601String(),
                'activeCalories': data.activeCalories,
                'basalCalories': data.basalCalories,
              })
          .toList();

      await _storage.saveExerciseDataBatch(batch);

      // Update cache
      for (final data in newData) {
        final dateId = _dateToId(data.date);
        _exerciseCache[dateId] = {
          'date': data.date.toIso8601String(),
          'activeCalories': data.activeCalories,
          'basalCalories': data.basalCalories,
        };
      }

      // Update display for selected date
      final selectedDateId = _dateToId(_selectedDate);
      final selectedData = _exerciseCache[selectedDateId];
      if (selectedData != null && mounted) {
        setState(() {
          _exerciseCalories = selectedData['activeCalories'] as int? ?? 0;
        });
      }
    }
  }

  /// Syncs historical health data from Health Connect to Firestore
  Future<void> _syncHistoricalHealthData() async {
    final hasPermissions = await _healthService.hasPermissions();
    if (!hasPermissions) return;

    // Get sync start date (healthConnectedDate or first entry date)
    final profile = await _storage.loadProfile();
    DateTime? startDate;

    final healthConnectedDateStr = profile?['healthConnectedDate'] as String?;
    if (healthConnectedDateStr != null) {
      startDate = DateTime.tryParse(healthConnectedDateStr);
    }

    // Fallback to first entry date if no healthConnectedDate
    if (startDate == null && _entries.isNotEmpty) {
      final sortedDates = _entries.map((e) => e.dateTime).toList()..sort();
      startDate = sortedDates.first;
    }

    // If still no date, use 30 days ago as default
    startDate ??= DateTime.now().subtract(const Duration(days: 30));

    // Get existing dates from cache
    final existingDates = _exerciseCache.keys.toSet();

    // Sync from Health Connect
    debugPrint('HomeScreen: Starting historical sync from $startDate');
    final newData = await _healthService.syncHistoricalData(
      startDate: startDate,
      existingDates: existingDates,
    );

    if (newData.isNotEmpty) {
      // Save to Firestore
      final batch = newData
          .map(
            (data) => {
              'date': data.date.toIso8601String(),
              'activeCalories': data.activeCalories,
              'basalCalories': data.basalCalories,
            },
          )
          .toList();

      await _storage.saveExerciseDataBatch(batch);

      // Update cache
      for (final data in newData) {
        final dateId = _dateToId(data.date);
        _exerciseCache[dateId] = {
          'date': data.date.toIso8601String(),
          'activeCalories': data.activeCalories,
          'basalCalories': data.basalCalories,
        };
      }

      // Update display for selected date if it was synced
      final selectedDateId = _dateToId(_selectedDate);
      final selectedData = _exerciseCache[selectedDateId];
      if (selectedData != null && mounted) {
        setState(() {
          _exerciseCalories = selectedData['activeCalories'] as int? ?? 0;
        });
      }

      debugPrint('HomeScreen: Synced ${newData.length} days of exercise data');
    } else {
      debugPrint('HomeScreen: No new exercise data to sync');
    }

    // Debug: try to fetch all health data
    await _healthService.debugFetchAllData();

    // Sync weight data (always, regardless of exercise data)
    await _syncWeightData(startDate);
  }

  /// Syncs weight data from Health Connect to Firestore
  Future<void> _syncWeightData(DateTime startDate) async {
    // Get existing weight dates
    final existingWeightDates = _weights
        .map((w) => _dateToId(w.dateTime))
        .toSet();

    // For weight, look back further (90 days or startDate, whichever is earlier)
    final ninetyDaysAgo = DateTime.now().subtract(const Duration(days: 90));
    final weightStartDate = startDate.isBefore(ninetyDaysAgo)
        ? startDate
        : ninetyDaysAgo;

    // Sync from Health Connect
    debugPrint('HomeScreen: Starting weight sync from $weightStartDate');
    final newWeightData = await _healthService.syncWeightData(
      startDate: weightStartDate,
      existingDates: existingWeightDates,
    );

    if (newWeightData.isEmpty) {
      debugPrint('HomeScreen: No new weight data to sync');
      return;
    }

    // Save to Firestore and update local state
    final newEntries = <WeightEntry>[];
    for (final data in newWeightData) {
      final entry = WeightEntry.create(
        weight: data.weightKg,
        date: data.dateTime,
      );
      await _storage.saveWeight(entry);
      newEntries.add(entry);
    }

    // Update local state
    if (mounted && newEntries.isNotEmpty) {
      setState(() {
        _weights.addAll(newEntries);
        // Sort by date descending
        _weights.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      });
    }

    debugPrint('HomeScreen: Synced ${newEntries.length} weight entries');
  }

  /// Formats a date as YYYY-MM-DD
  String _dateToId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Gets the budget that was active on a specific date
  int _getBudgetForDate(DateTime date) {
    final dateKey = _dateToId(date);

    // Find the most recent budget entry <= date
    // Budget history is sorted by effectiveDate descending
    for (final budget in _budgetHistory) {
      final effectiveDate = budget['effectiveDate'] as String?;
      if (effectiveDate != null && effectiveDate.compareTo(dateKey) <= 0) {
        return budget['calorieBudget'] as int? ?? _calorieBudget;
      }
    }

    // Fallback to default budget
    return _calorieBudget;
  }

  /// Returns only entries from the selected date
  List<FoodEntry> get _selectedDateEntries {
    return _entries.where((entry) {
      return entry.dateTime.year == _selectedDate.year &&
          entry.dateTime.month == _selectedDate.month &&
          entry.dateTime.day == _selectedDate.day;
    }).toList();
  }

  /// Navigate to previous day
  void _goToPreviousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
    _loadHealthData();
  }

  /// Navigate to next day (only if not already at today)
  void _goToNextDay() {
    if (_isToday) return;
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
    _loadHealthData();
  }

  /// Show date picker
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _loadHealthData();
    }
  }

  /// Check if selected date is today
  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  /// Returns selected date's entries filtered by meal type
  List<FoodEntry> _entriesForMeal(MealType mealType) {
    return _selectedDateEntries
        .where((entry) => entry.mealType == mealType)
        .toList();
  }

  /// Calculates calories for a specific meal
  int _caloriesForMeal(MealType mealType) {
    return _entriesForMeal(
      mealType,
    ).fold(0, (sum, entry) => sum + entry.calories);
  }

  /// Calculates total calories for selected date
  int get _totalCalories {
    return _selectedDateEntries.fold(0, (sum, entry) => sum + entry.calories);
  }

  /// Calculates total macros for selected date
  double get _totalFat =>
      _selectedDateEntries.fold(0.0, (sum, entry) => sum + entry.fat);
  double get _totalCarbs =>
      _selectedDateEntries.fold(0.0, (sum, entry) => sum + entry.carbs);
  double get _totalProtein =>
      _selectedDateEntries.fold(0.0, (sum, entry) => sum + entry.protein);
  double get _totalSugars =>
      _selectedDateEntries.fold(0.0, (sum, entry) => sum + entry.sugars);

  // ============= Week calculation helpers for dashboard =============

  /// Check if two dates are the same day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Get the start of the week containing _selectedDate
  DateTime get _weekStart {
    if (_weekStartDay == 'sunday') {
      // Sunday is weekday 7 in Dart
      final daysToSubtract = _selectedDate.weekday % 7;
      return _selectedDate.subtract(Duration(days: daysToSubtract));
    } else {
      // Monday is weekday 1
      return _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    }
  }

  /// Get entries for a specific day
  List<FoodEntry> _entriesForDay(DateTime day) {
    return _entries.where((e) => _isSameDay(e.dateTime, day)).toList();
  }

  /// Get daily calorie totals for the week (7 values, Mon-Sun)
  List<int> get _weeklyCalories {
    return List.generate(7, (i) {
      final day = _weekStart.add(Duration(days: i));
      return _entriesForDay(day).fold(0, (sum, e) => sum + e.calories);
    });
  }

  /// Get daily macro totals for the week
  List<Map<String, double>> get _weeklyMacros {
    return List.generate(7, (i) {
      final day = _weekStart.add(Duration(days: i));
      final entries = _entriesForDay(day);
      return {
        'fat': entries.fold(0.0, (sum, e) => sum + e.fat),
        'carbs': entries.fold(0.0, (sum, e) => sum + e.carbs),
        'protein': entries.fold(0.0, (sum, e) => sum + e.protein),
      };
    });
  }

  // ============= Streak calculation helpers =============

  /// Check if a day was successful (has entries AND under budget)
  bool _isDaySuccessful(DateTime day) {
    final entries = _entriesForDay(day);
    if (entries.isEmpty) return false;
    final dayCalories = entries.fold(0, (sum, e) => sum + e.calories);
    final dayBudget = _getBudgetForDate(day);
    return dayCalories <= dayBudget;
  }

  /// Calculate current streak (consecutive days under budget ending today)
  int get _currentStreak {
    int streak = 0;
    DateTime day = DateTime.now();

    while (_isDaySuccessful(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }

    return streak;
  }

  /// Calculate number of perfect weeks (all 7 days under budget)
  int get _perfectWeeksCount {
    if (_entries.isEmpty) return 0;

    // Find earliest entry date
    final sortedDates = _entries.map((e) => e.dateTime).toList()..sort();
    final earliestDate = sortedDates.first;

    int perfectWeeks = 0;

    // Get the week start for earliest date
    DateTime weekStart;
    if (_weekStartDay == 'sunday') {
      weekStart = earliestDate.subtract(
        Duration(days: earliestDate.weekday % 7),
      );
    } else {
      weekStart = earliestDate.subtract(
        Duration(days: earliestDate.weekday - 1),
      );
    }

    final now = DateTime.now();

    // Check each complete week
    while (weekStart.add(const Duration(days: 6)).isBefore(now)) {
      bool isPerfect = true;
      for (int i = 0; i < 7; i++) {
        if (!_isDaySuccessful(weekStart.add(Duration(days: i)))) {
          isPerfect = false;
          break;
        }
      }
      if (isPerfect) perfectWeeks++;
      weekStart = weekStart.add(const Duration(days: 7));
    }

    return perfectWeeks;
  }

  // ============= Weight tracking helpers =============

  /// Convert weight from kg to display unit
  double _displayWeight(double kg) {
    return _useMetric ? kg : kg * 2.20462;
  }

  /// Convert weight from display unit to kg for storage
  double _storageWeight(double displayValue) {
    return _useMetric ? displayValue : displayValue / 2.20462;
  }

  /// Weight unit label
  String get _weightUnit => _useMetric ? 'kg' : 'lb';

  /// Get weight entry for a specific day
  WeightEntry? _weightForDay(DateTime day) {
    try {
      return _weights.firstWhere((w) => _isSameDay(w.dateTime, day));
    } catch (_) {
      return null;
    }
  }

  /// Get weekly weight data (7 values, null if no entry)
  List<double?> get _weeklyWeights {
    return List.generate(7, (i) {
      final day = _weekStart.add(Duration(days: i));
      return _weightForDay(day)?.weight;
    });
  }

  /// Get latest weight entry
  WeightEntry? get _latestWeight {
    if (_weights.isEmpty) return null;
    return _weights.first; // Already sorted descending
  }

  /// Calculate weight change over past month
  double? get _weightChangeMonth {
    if (_weights.isEmpty) return null;
    final now = DateTime.now();
    final monthAgo = now.subtract(const Duration(days: 30));

    final current = _latestWeight?.weight;
    final olderWeights = _weights.where((w) => w.dateTime.isBefore(monthAgo));
    final older = olderWeights.isNotEmpty ? olderWeights.first.weight : null;

    if (current == null || older == null) return null;
    return current - older;
  }

  /// Suggested calories per meal (based on stored budgets or default distribution)
  int _suggestedCalories(MealType mealType) {
    final mealKey = mealType.name; // 'breakfast', 'lunch', 'dinner', 'snacks'
    final mealBudget = _mealBudgets[mealKey];
    final todayBudget = _getBudgetForDate(_selectedDate);

    // Default percentages if no custom budget set
    final defaultPercents = {
      'breakfast': 0.25,
      'lunch': 0.30,
      'dinner': 0.30,
      'snacks': 0.15,
    };

    if (mealBudget != null) {
      final value = mealBudget['value'] as int? ?? 0;
      final isPercent = mealBudget['isPercent'] as bool? ?? true;

      if (isPercent) {
        return (todayBudget * value / 100).round();
      } else {
        return value; // Absolute calories
      }
    }

    // Fallback to default percentages
    return (todayBudget * defaultPercents[mealKey]!).round();
  }

  /// Opens the add food screen and saves the new entry
  Future<void> _addFood(MealType mealType) async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) =>
            AddFoodScreen(mealType: mealType, date: _selectedDate),
      ),
    );

    // User cancelled or closed the screen
    if (result == null) return;

    // Handle both single entry and list of entries (from meals)
    final entries = result is List<FoodEntry> ? result : [result as FoodEntry];

    // Add the entries and save to Firestore
    setState(() {
      for (final entry in entries) {
        _entries.insert(0, entry); // Add at beginning (newest first)
      }
    });
    await _storage.saveEntries(entries);
  }

  /// Shows a bottom sheet to select which meal to add food to
  void _showMealSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add food to...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.breakfast_dining),
              title: const Text('Breakfast'),
              onTap: () {
                Navigator.pop(context);
                _addFood(MealType.breakfast);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lunch_dining),
              title: const Text('Lunch'),
              onTap: () {
                Navigator.pop(context);
                _addFood(MealType.lunch);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dinner_dining),
              title: const Text('Dinner'),
              onTap: () {
                Navigator.pop(context);
                _addFood(MealType.dinner);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cookie),
              title: const Text('Snacks'),
              onTap: () {
                Navigator.pop(context);
                _addFood(MealType.snacks);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Deletes an entry from Firestore
  Future<void> _deleteEntry(String id) async {
    setState(() {
      _entries.removeWhere((entry) => entry.id == id);
    });
    await _storage.deleteEntry(id);
  }

  /// Clears all entries for a meal
  Future<void> _clearMealEntries(List<FoodEntry> entries) async {
    final ids = entries.map((e) => e.id).toList();
    setState(() {
      _entries.removeWhere((entry) => ids.contains(entry.id));
    });
    for (final id in ids) {
      await _storage.deleteEntry(id);
    }
  }

  /// Creates a saved meal from the current entries in a meal card
  Future<void> _createMealFromEntries(
    MealType mealType,
    List<FoodEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return;
    }

    // Load existing meals to check for duplicates
    final existingMeals = await _storage.loadMeals();
    final existingNames = existingMeals
        .map((m) => m.name.toLowerCase())
        .toSet();

    final nameController = TextEditingController();
    final totalCalories = entries.fold(0, (sum, e) => sum + e.calories);

    // Track selected meal types - default to the current meal type
    final selectedMealTypes = <MealType>{mealType};
    String? errorText;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          title: const Text('Create Meal'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Meal name',
                    hintText: 'e.g., Morning Smoothie',
                    errorText: errorText,
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Show in:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: MealType.values.map((type) {
                    final isSelected = selectedMealTypes.contains(type);
                    return FilterChip(
                      label: Text(_mealName(type)),
                      selected: isSelected,
                      onSelected: (selected) {
                        setDialogState(() {
                          if (selected) {
                            selectedMealTypes.add(type);
                          } else if (selectedMealTypes.length > 1) {
                            selectedMealTypes.remove(type);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  '${entries.length} items • $totalCalories cal',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                ...entries.map(
                  (e) => Text(
                    '• ${e.name} (${e.calories} cal)',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = 'Please enter a name');
                  return;
                }
                if (existingNames.contains(name.toLowerCase())) {
                  setDialogState(
                    () => errorText = 'A meal with this name already exists',
                  );
                  return;
                }
                Navigator.pop(context);
                _saveMeal(name, entries, selectedMealTypes.toList());
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves a meal to storage
  Future<void> _saveMeal(
    String name,
    List<FoodEntry> entries,
    List<MealType> mealTypes,
  ) async {
    final meal = Meal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      items: entries
          .map(
            (e) => MealItem(
              name: e.name,
              calories: e.calories,
              fat: e.fat,
              carbs: e.carbs,
              protein: e.protein,
              sugars: e.sugars,
            ),
          )
          .toList(),
      mealTypes: mealTypes,
    );
    await _storage.saveMeal(meal);
  }

  /// Returns the display name for a meal type
  String _mealName(MealType mealType) {
    switch (mealType) {
      case MealType.breakfast:
        return 'Breakfast';
      case MealType.lunch:
        return 'Lunch';
      case MealType.dinner:
        return 'Dinner';
      case MealType.snacks:
        return 'Snacks';
    }
  }

  /// Formats selected date for display in app bar
  String get _shortFormattedDate {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[_selectedDate.weekday - 1]}, ${months[_selectedDate.month - 1]} ${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  /// Formats selected date for display in content
  String get _formattedDate {
    if (_isToday) {
      return 'Today';
    }
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    if (_selectedDate.year == yesterday.year &&
        _selectedDate.month == yesterday.month &&
        _selectedDate.day == yesterday.day) {
      return 'Yesterday';
    }
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';
  }

  /// Builds the date navigation widget for the app bar
  Widget _buildDateNavigation() {
    final iconColor = Theme.of(context).colorScheme.onSurface;
    final disabledColor = Theme.of(context).colorScheme.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.chevron_left, size: 28, color: iconColor),
          onPressed: _goToPreviousDay,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        GestureDetector(
          onTap: _selectDate,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 22, color: iconColor),
              const SizedBox(width: 8),
              Text(
                _shortFormattedDate,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            size: 28,
            color: _isToday ? disabledColor : iconColor,
          ),
          onPressed: _isToday ? null : _goToNextDay,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _buildDateNavigation(),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const _ProfilePage()),
                  );
                  break;
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ).then((_) => _loadData());
                  break;
                case 'logout':
                  _authService.signOut();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'profile', child: Text('Profile')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentTab == 0
          ? _buildDashboardTab()
          : _buildLogTab(),
      bottomNavigationBar: BottomAppBar(
        color: backgroundColor,
        elevation: 0,
        height: 60,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Dashboard tab
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _currentTab = 0),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      color: _currentTab == 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 12,
                        color: _currentTab == 0
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Log tab
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _currentTab = 1),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      color: _currentTab == 1
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    Text(
                      'Log',
                      style: TextStyle(
                        fontSize: 12,
                        color: _currentTab == 1
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the Dashboard tab content
  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        children: [
          _buildDashboardCaloriesCard(),
          const SizedBox(height: 8),
          _buildDashboardMacrosCard(),
          const SizedBox(height: 8),
          _buildDashboardStreakCard(),
          const SizedBox(height: 8),
          _buildDashboardWeightCard(),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  /// Builds the Calories card for the dashboard
  Widget _buildDashboardCaloriesCard() {
    final budget = _getBudgetForDate(_selectedDate);
    final todayCalories = _totalCalories;
    final remaining = budget - todayCalories;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CaloriesDetailScreen(
              initialDate: _selectedDate,
              calorieBudget: budget,
              entries: _entries,
              exerciseData: _exerciseCache,
              weekStartDay: _weekStartDay,
            ),
          ),
        );
      },
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'Calories',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Circular progress + weekly bars
            Row(
              children: [
                // Left: circular progress with remaining
                _buildDashboardCircularProgress(remaining),
                const SizedBox(width: 24),
                // Right: weekly bar chart
                Expanded(child: _buildWeeklyCaloriesBars()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the circular progress indicator for dashboard
  Widget _buildDashboardCircularProgress(int remaining) {
    final budget = _getBudgetForDate(_selectedDate);
    final progress = _totalCalories / budget;
    final isOver = remaining < 0;

    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(100, 100),
            painter: _ArcPainter(
              progress: progress.clamp(0.0, 1.0),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              progressColor: isOver ? Colors.red : Colors.green,
              strokeWidth: 12,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${remaining.abs()}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isOver ? Colors.red : Colors.green,
                ),
              ),
              Text(
                isOver ? 'over' : 'under',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the weekly calorie bars for dashboard
  Widget _buildWeeklyCaloriesBars() {
    final days = _weekStartDay == 'sunday'
        ? ['S', 'M', 'T', 'W', 'T', 'F', 'S']
        : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final calories = _weeklyCalories;
    const barHeight = 100.0;

    return SizedBox(
      height: barHeight + 38, // bar + spacing + label
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(7, (i) {
          final day = _weekStart.add(Duration(days: i));
          final dayBudget = _getBudgetForDate(day);
          final dayCalories = calories[i];
          final fillRatio = (dayCalories / dayBudget).clamp(0.0, 1.0);
          final isToday = _isSameDay(day, now);
          final isSelected = _isSameDay(day, _selectedDate);
          final isOverBudget = dayCalories > dayBudget;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDate = day;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    // Bar with gray background and colored fill
                    Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          height: barHeight * fillRatio,
                          decoration: BoxDecoration(
                            color: isOverBudget ? Colors.red : Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Day label
                    Text(
                      days[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: (isSelected || isToday)
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isToday
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Builds the Macronutrients card for the dashboard
  Widget _buildDashboardMacrosCard() {
    final macros = _weeklyMacros;

    // Calculate weekly averages
    double totalFat = 0, totalCarbs = 0, totalProtein = 0;
    for (final dayMacros in macros) {
      totalFat += dayMacros['fat']!;
      totalCarbs += dayMacros['carbs']!;
      totalProtein += dayMacros['protein']!;
    }
    final totalMacros = totalFat + totalCarbs + totalProtein;
    final fatPercent = totalMacros > 0
        ? (totalFat / totalMacros * 100).round()
        : 0;
    final carbsPercent = totalMacros > 0
        ? (totalCarbs / totalMacros * 100).round()
        : 0;
    final proteinPercent = totalMacros > 0
        ? (totalProtein / totalMacros * 100).round()
        : 0;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Macronutrients',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            children: [
              _buildMacroLegendDot(Colors.amber, 'Fat'),
              const SizedBox(width: 16),
              _buildMacroLegendDot(Colors.purple.shade300, 'Carbs'),
              const SizedBox(width: 16),
              _buildMacroLegendDot(const Color(0xFF5CCECB), 'Protein'),
            ],
          ),
          const SizedBox(height: 16),
          // Stacked bar chart
          _buildWeeklyMacrosBars(),
          const SizedBox(height: 16),
          // Average chips
          Row(
            children: [
              Text(
                'Average',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(width: 12),
              _buildAverageChip('$fatPercent%', Colors.amber.shade100),
              const SizedBox(width: 8),
              _buildAverageChip('$carbsPercent%', Colors.purple.shade50),
              const SizedBox(width: 8),
              _buildAverageChip('$proteinPercent%', const Color(0xFFD4F5F4)),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds a legend dot with label
  Widget _buildMacroLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  /// Builds an average percentage chip
  Widget _buildAverageChip(String text, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }

  /// Builds the weekly macros stacked bars
  Widget _buildWeeklyMacrosBars() {
    final days = _weekStartDay == 'sunday'
        ? ['S', 'M', 'T', 'W', 'T', 'F', 'S']
        : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final macros = _weeklyMacros;
    const barHeight = 100.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final dayMacros = macros[i];
        final day = _weekStart.add(Duration(days: i));
        final isToday = _isSameDay(day, now);
        final isSelected = _isSameDay(day, _selectedDate);

        final total =
            dayMacros['fat']! + dayMacros['carbs']! + dayMacros['protein']!;
        final fatFlex = total > 0
            ? (dayMacros['fat']! / total * 100).round()
            : 0;
        final carbsFlex = total > 0
            ? (dayMacros['carbs']! / total * 100).round()
            : 0;
        final proteinFlex = total > 0
            ? (dayMacros['protein']! / total * 100).round()
            : 0;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = day;
            });
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Stacked bar
              Container(
                width: 24,
                height: barHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: total > 0
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Column(
                          children: [
                            // Protein (top - teal)
                            if (proteinFlex > 0)
                              Expanded(
                                flex: proteinFlex,
                                child: Container(
                                  color: const Color(0xFF5CCECB),
                                ),
                              ),
                            // Carbs (middle - light purple)
                            if (carbsFlex > 0)
                              Expanded(
                                flex: carbsFlex,
                                child: Container(color: Colors.purple.shade300),
                              ),
                            // Fat (bottom - amber)
                            if (fatFlex > 0)
                              Expanded(
                                flex: fatFlex,
                                child: Container(color: Colors.amber),
                              ),
                          ],
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              // Day label
              Text(
                days[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: (isSelected || isToday)
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isToday
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// Builds the Streaks card for the dashboard
  Widget _buildDashboardStreakCard() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Streaks',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Stats row
          Row(
            children: [
              Expanded(
                child: _buildStreakStat(value: _currentStreak, label: 'days'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStreakStat(
                  value: _perfectWeeksCount,
                  label: 'perfect weeks',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // GitHub-style grid
          _buildStreakGrid(),
        ],
      ),
    );
  }

  Widget _buildStreakStat({required int value, required String label}) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  /// Builds the weekly streak boxes (7 days in a row)
  Widget _buildStreakGrid() {
    final now = DateTime.now();
    final dayLabels = _weekStartDay == 'sunday'
        ? ['S', 'M', 'T', 'W', 'T', 'F', 'S']
        : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (dayIndex) {
        final day = _weekStart.add(Duration(days: dayIndex));
        final isFuture = day.isAfter(now);
        final isToday = _isSameDay(day, now);
        final isSelected = _isSameDay(day, _selectedDate);
        final entries = _entriesForDay(day);
        final hasEntries = entries.isNotEmpty;
        final dayCalories = entries.fold(0, (sum, e) => sum + e.calories);
        final dayBudget = _getBudgetForDate(day);
        final isUnderBudget = dayCalories <= dayBudget;

        Color cellColor;
        if (isFuture) {
          cellColor = Theme.of(context).colorScheme.surfaceContainerHighest;
        } else if (hasEntries && isUnderBudget) {
          cellColor = Colors.green;
        } else if (hasEntries && !isUnderBudget) {
          cellColor = Colors.red;
        } else {
          cellColor = Theme.of(context).colorScheme.surfaceContainerHighest;
        }

        return Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cellColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dayLabels[dayIndex],
              style: TextStyle(
                fontSize: 12,
                fontWeight: (isSelected || isToday)
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: isToday
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        );
      }),
    );
  }

  /// Builds the Weight card for the dashboard
  Widget _buildDashboardWeightCard() {
    final latest = _latestWeight;
    final change = _weightChangeMonth;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Text(
                'Weight',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (change != null)
                Text(
                  '${change >= 0 ? '↑' : '↓'}${_displayWeight(change.abs()).toStringAsFixed(1)} $_weightUnit',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
          if (change != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'past month',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Chart
          SizedBox(height: 120, child: _buildWeightChart()),
          const SizedBox(height: 16),
          // Bottom row: latest weight + record button
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latest != null ? 'Latest' : 'No data',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Text(
                    latest != null
                        ? '${_displayWeight(latest.weight).toStringAsFixed(1)} $_weightUnit'
                        : '--',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!_isFutureDate)
                FilledButton(
                  onPressed: _showRecordWeightDialog,
                  child: const Text('Record'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Check if selected date is in the future
  bool get _isFutureDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return selected.isAfter(today);
  }

  /// Builds the weight line chart
  Widget _buildWeightChart() {
    final weights = _weeklyWeights;
    final days = _weekStartDay == 'sunday'
        ? ['S', 'M', 'T', 'W', 'T', 'F', 'S']
        : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    // Find min/max for scaling
    final validWeights = weights.whereType<double>().toList();
    if (validWeights.isEmpty) {
      return Center(
        child: Text(
          'No weight data',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    var minWeight = validWeights.reduce((a, b) => a < b ? a : b);
    var maxWeight = validWeights.reduce((a, b) => a > b ? a : b);

    // Include goal weight in range if set
    if (_targetWeight != null) {
      minWeight = minWeight < _targetWeight! ? minWeight : _targetWeight!;
      maxWeight = maxWeight > _targetWeight! ? maxWeight : _targetWeight!;
    }

    // Add padding
    minWeight -= 1;
    maxWeight += 1;
    final midWeight = (minWeight + maxWeight) / 2;

    // Convert to display units for scale labels
    final displayMin = _displayWeight(minWeight);
    final displayMax = _displayWeight(maxWeight);
    final displayMid = _displayWeight(midWeight);

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              // Scale on the left
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${displayMax.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Text(
                    '${displayMid.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Text(
                    '${displayMin.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Chart area
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _WeightChartPainter(
                    weights: weights,
                    minWeight: minWeight,
                    maxWeight: maxWeight,
                    goalWeight: _targetWeight,
                    goalLineColor: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.5),
                    gridColor: Colors.grey.shade200,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 28), // Space for scale alignment
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(7, (i) {
                  final day = _weekStart.add(Duration(days: i));
                  final now = DateTime.now();
                  final isToday = _isSameDay(day, now);
                  final isSelected = _isSameDay(day, _selectedDate);
                  return Text(
                    days[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: (isSelected || isToday)
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isToday
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.outline,
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Shows dialog to record weight
  Future<void> _showRecordWeightDialog() async {
    // Don't allow recording weight for future dates
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    if (selected.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot record weight for future dates')),
      );
      return;
    }

    final unit = _weightUnit;
    final existingEntry = _weightForDay(_selectedDate);
    final controller = TextEditingController(
      text: existingEntry != null
          ? _displayWeight(existingEntry.weight).toStringAsFixed(1)
          : '',
    );

    // Format date for display
    final dateStr = _isToday
        ? 'Today'
        : '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingEntry != null ? 'Update Weight' : 'Record Weight'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Weight ($unit)',
                suffixText: unit,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final weight = double.tryParse(controller.text);
              if (weight != null && weight > 0) {
                Navigator.pop(context, weight);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      // Convert to kg for storage
      final weightInKg = _storageWeight(result);

      if (existingEntry != null) {
        // Update existing entry
        final updatedEntry = WeightEntry(
          id: existingEntry.id,
          weight: weightInKg,
          dateTime: existingEntry.dateTime,
        );
        await _storage.saveWeight(updatedEntry);
        setState(() {
          final index = _weights.indexWhere((w) => w.id == existingEntry.id);
          if (index != -1) {
            _weights[index] = updatedEntry;
          }
        });
      } else {
        // Create new entry
        final entry = WeightEntry.create(
          weight: weightInKg,
          date: _selectedDate,
        );
        await _storage.saveWeight(entry);
        setState(() {
          // Insert in correct position (sorted by date descending)
          final index = _weights.indexWhere(
            (w) => w.dateTime.isBefore(entry.dateTime),
          );
          if (index == -1) {
            _weights.add(entry);
          } else {
            _weights.insert(index, entry);
          }
        });
      }
    }
  }

  /// Builds the budget card content with circular progress and macros
  Widget _buildBudgetContent() {
    final budget = _getBudgetForDate(_selectedDate);
    final eaten = _totalCalories;
    final remaining = budget - eaten + _exerciseCalories;
    final burned = _exerciseCalories;
    final progress = eaten / budget;
    final isOver = remaining < 0;

    // Macro goals (example values - could be made configurable)
    final carbsGoal = 258;
    final proteinGoal = 103;
    final fatGoal = 68;

    // Colors based on over/under budget
    final progressColor = isOver ? Colors.red : const Color(0xFF34D399);

    return Column(
      children: [
        // Circular progress with eaten/remaining/burned
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Eaten
            Column(
              children: [
                Text(
                  '$eaten',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Eaten',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
            // Circular progress
            SizedBox(
              width: 130,
              height: 130,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(130, 130),
                    painter: _CircularProgressPainter(
                      progress: progress.clamp(0.0, 1.0),
                      backgroundColor: Colors.grey.shade200,
                      progressColor: progressColor,
                      strokeWidth: 10,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${isOver ? remaining.abs() : remaining}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: isOver ? Colors.red : null,
                        ),
                      ),
                      Text(
                        isOver ? 'Over' : 'Remaining',
                        style: TextStyle(
                          fontSize: 14,
                          color: isOver ? Colors.red : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Burned
            Column(
              children: [
                Text(
                  '$burned',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Burned',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Macro progress bars
        Row(
          children: [
            Expanded(
              child: _buildMacroProgress(
                'Carbs',
                _totalCarbs.round(),
                carbsGoal,
                Colors.purple.shade300,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMacroProgress(
                'Protein',
                _totalProtein.round(),
                proteinGoal,
                const Color(0xFF5CCECB),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMacroProgress(
                'Fat',
                _totalFat.round(),
                fatGoal,
                Colors.amber,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds a macro progress bar with label and values
  Widget _buildMacroProgress(String label, int current, int goal, Color color) {
    final progress = (current / goal).clamp(0.0, 1.0);
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$current / $goal g',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Builds a meal card with name, calories, and add button
  Widget _buildMealCard(MealType mealType) {
    final calories = _caloriesForMeal(mealType);
    final entries = _entriesForMeal(mealType);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Meal name and calories
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mealName(mealType),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$calories Cal',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              // Three-dot menu (only show when there are entries)
              if (entries.isNotEmpty) _buildMealCardMenu(mealType, entries),
            ],
          ),
          // Food entries
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.name,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      '${entry.calories} Cal',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      onPressed: () => _deleteEntry(entry.id),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // Add button
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _addFood(mealType),
              child: const Text('Add Food'),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the three-dot menu for cards
  Widget _buildCardMenu() {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: Theme.of(context).colorScheme.outline,
      ),
      onSelected: (value) {},
      itemBuilder: (context) => [],
    );
  }

  /// Builds the three-dot menu for meal cards
  Widget _buildMealCardMenu(MealType mealType, List<FoodEntry> entries) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: Theme.of(context).colorScheme.outline,
      ),
      onSelected: (value) {
        switch (value) {
          case 'create_meal':
            _createMealFromEntries(mealType, entries);
            break;
          case 'clear_all':
            _clearMealEntries(entries);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'create_meal',
          child: Text('Create Meal'),
        ),
        if (entries.isNotEmpty)
          const PopupMenuItem(
            value: 'clear_all',
            child: Text('Clear All'),
          ),
      ],
    );
  }

  /// Builds the Log tab content (meal cards)
  Widget _buildLogTab() {
    final budget = _getBudgetForDate(_selectedDate);
    final remaining = budget - _totalCalories;
    final progress = _totalCalories / budget;

    return Stack(
      children: [
        // Scrollable content with pull-to-refresh
        RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              const SizedBox(height: 16),
              // Budget card
              AppCard(
                title: 'Budget',
                child: _buildBudgetContent(),
              ),
              const SizedBox(height: 8),
              // Breakfast card
              _buildMealCard(MealType.breakfast),
              const SizedBox(height: 8),
              // Lunch card
              _buildMealCard(MealType.lunch),
              const SizedBox(height: 8),
              // Dinner card
              _buildMealCard(MealType.dinner),
              const SizedBox(height: 8),
              // Snacks card
              _buildMealCard(MealType.snacks),
              const SizedBox(height: 80), // Space for bottom nav
            ],
          ),
        ),
        // Floating bar
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          top: _showFloatingBar ? 0 : -60,
          left: 0,
          right: 0,
          child: _buildFloatingBar(remaining, progress),
        ),
      ],
    );
  }

  /// Builds the main calorie budget card
  Widget _buildCalorieCard(int remaining, double progress) {
    final budget = _getBudgetForDate(_selectedDate);
    return AppCard(
      title: 'Budget: $budget cals',
      child: Column(
        children: [
          // Circular progress with stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Food consumed
              Column(
                children: [
                  Text(
                    'Food',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_totalCalories',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Circular progress
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(120, 120),
                      painter: _ArcPainter(
                        progress: progress.clamp(0.0, 1.0),
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        progressColor: remaining >= 0 ? Colors.green : Colors.red,
                        strokeWidth: 14,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${remaining.abs()}',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: remaining >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                        Text(
                          remaining >= 0 ? 'Under' : 'Over',
                          style: TextStyle(
                            fontSize: 14,
                            color: remaining >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Exercise
              Column(
                children: [
                  Text(
                    'Exercise',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_exerciseCalories',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Spacing between calories and macros
          const SizedBox(height: 20),
          // Macros row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMacroColumn('Fat', _totalFat),
              _buildMacroColumn('Carbs', _totalCarbs),
              _buildMacroColumn('Protein', _totalProtein),
              _buildMacroColumn('Sugar', _totalSugars),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroColumn(String label, double value) {
    return Column(
      children: [
        Text(
          '${value.round()}g',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  /// Builds the floating progress bar that shows when scrolled
  Widget _buildFloatingBar(int remaining, double progress) {
    final budget = _getBudgetForDate(_selectedDate);
    final isOver = remaining < 0;
    final color = isOver ? Colors.red : const Color(0xFF34D399);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Calories info
            Text(
              '$_totalCalories',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              ' / $budget cal',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 12),
            // Progress bar
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Remaining
            Text(
              '${remaining.abs()} ${isOver ? 'over' : 'left'}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [_buildMenuButton(context)],
      ),
      body: const Center(child: Text('Profile')),
    );
  }
}

Widget _buildMenuButton(BuildContext context) {
  final authService = AuthService();
  return PopupMenuButton<String>(
    icon: const Icon(Icons.menu),
    onSelected: (value) {
      switch (value) {
        case 'profile':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const _ProfilePage()),
          );
          break;
        case 'settings':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
          break;
        case 'logout':
          authService.signOut();
          Navigator.of(context).popUntil((route) => route.isFirst);
          break;
      }
    },
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'profile', child: Text('Profile')),
      const PopupMenuItem(value: 'settings', child: Text('Settings')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'logout', child: Text('Logout')),
    ],
  );
}

/// Custom painter for the weight line chart
class _WeightChartPainter extends CustomPainter {
  final List<double?> weights;
  final double minWeight;
  final double maxWeight;
  final double? goalWeight;
  final Color goalLineColor;
  final Color gridColor;

  _WeightChartPainter({
    required this.weights,
    required this.minWeight,
    required this.maxWeight,
    this.goalWeight,
    required this.goalLineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Clip to chart bounds
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final range = maxWeight - minWeight;
    if (range <= 0) {
      canvas.restore();
      return;
    }

    final stepX = size.width / 6; // 7 points, 6 gaps

    // Draw horizontal grid lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw goal weight dashed line
    if (goalWeight != null &&
        goalWeight! >= minWeight &&
        goalWeight! <= maxWeight) {
      final goalY =
          size.height - ((goalWeight! - minWeight) / range * size.height);
      final goalPaint = Paint()
        ..color = goalLineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      _drawDashedLine(
        canvas,
        Offset(0, goalY),
        Offset(size.width, goalY),
        goalPaint,
      );
    }

    // Calculate and draw trend line
    final validPoints = <int, double>{};
    for (int i = 0; i < weights.length; i++) {
      if (weights[i] != null) {
        validPoints[i] = weights[i]!;
      }
    }

    if (validPoints.length >= 2) {
      // Linear regression
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      for (final entry in validPoints.entries) {
        sumX += entry.key;
        sumY += entry.value;
        sumXY += entry.key * entry.value;
        sumX2 += entry.key * entry.key;
      }
      final n = validPoints.length;
      final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      final intercept = (sumY - slope * sumX) / n;

      // Calculate start and end points of trend line (full width)
      final startWeight = slope * 0 + intercept;
      final endWeight = slope * 6 + intercept;

      final startY =
          size.height - ((startWeight - minWeight) / range * size.height);
      final endY =
          size.height - ((endWeight - minWeight) / range * size.height);

      // Color based on direction (green = losing weight, red = gaining)
      final trendColor = slope <= 0
          ? Colors.green.shade400
          : Colors.red.shade400;
      final trendPaint = Paint()
        ..color = trendColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      _drawDashedLine(
        canvas,
        Offset(0, startY),
        Offset(size.width, endY),
        trendPaint,
      );
    }

    // Draw line connecting points
    final path = Path();
    bool started = false;
    final points = <Offset>[];

    for (int i = 0; i < weights.length; i++) {
      final weight = weights[i];
      if (weight == null) continue;

      final x = i * stepX;
      final y = size.height - ((weight - minWeight) / range * size.height);
      final point = Offset(x, y);
      points.add(point);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw dots
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }

    canvas.restore();
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 3.0;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = sqrt(dx * dx + dy * dy);
    if (distance == 0) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    double currentDistance = 0;
    while (currentDistance < distance) {
      final startPoint = Offset(
        start.dx + unitX * currentDistance,
        start.dy + unitY * currentDistance,
      );
      final endDistance = (currentDistance + dashWidth).clamp(0.0, distance);
      final endPoint = Offset(
        start.dx + unitX * endDistance,
        start.dy + unitY * endDistance,
      );
      canvas.drawLine(startPoint, endPoint, paint);
      currentDistance += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Custom painter for drawing an arc that's open at the bottom (horseshoe shape)
class _ArcPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _ArcPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Arc spans 240 degrees (from 150° to 390°), leaving 120° open at bottom
    const startAngle = 150 * pi / 180; // Start at bottom-left
    const sweepAngle = 240 * pi / 180; // Sweep 240 degrees

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );

    // Draw progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor;
  }
}

/// Custom painter for drawing a circular progress arc open at the bottom
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Arc spans 240 degrees, leaving 120 degrees open at bottom
    const startAngle = 150 * pi / 180; // Start at bottom-left
    const sweepAngle = 240 * pi / 180; // Sweep 240 degrees

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );

    // Draw progress arc (starting from left, going clockwise)
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor;
  }
}
