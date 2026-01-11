import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/food.dart';
import '../models/food_entry.dart';
import '../models/meal.dart';
import '../services/food_search_service.dart';
import '../services/storage_service.dart';

/// Screen for adding food with search and tabs.
class AddFoodScreen extends StatefulWidget {
  final MealType mealType;
  final DateTime? date;

  const AddFoodScreen({super.key, required this.mealType, this.date});

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen>
    with SingleTickerProviderStateMixin {
  // Conversion constant
  static const double _gramsPerOunce = 28.3495;

  late TabController _tabController;
  final _searchController = TextEditingController();
  final _storage = StorageService();
  final _foodSearch = FoodSearchService();

  // Frequent foods from user's history (sorted by frequency)
  List<FoodEntry> _frequentFoods = [];

  // Recent foods from user's history (last 50 unique)
  List<FoodEntry> _recentFoods = [];

  // Saved meals
  List<Meal> _savedMeals = [];

  // User preferences
  bool _useMetric = true;

  // Search state
  String _searchQuery = '';
  List<Food> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  // Multi-select state
  List<FoodEntry> _selectedEntries = [];
  // Track portion info for editing (keyed by entry id)
  final Map<String, ({String amount, bool useServing, Food? food})> _portionInfo = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserPreferences();
    _loadRecentFoods();
    _loadMeals();
  }

  Future<void> _loadUserPreferences() async {
    final profile = await _storage.loadProfile();
    if (mounted && profile != null) {
      setState(() {
        _useMetric = profile['useMetric'] as bool? ?? true;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentFoods() async {
    final entries = await _storage.loadEntries();

    // Count frequency and track most recent entry for each food
    final frequencyMap = <String, int>{};
    final latestEntry = <String, FoodEntry>{};

    for (final entry in entries) {
      final key = entry.name.toLowerCase();
      frequencyMap[key] = (frequencyMap[key] ?? 0) + 1;
      latestEntry.putIfAbsent(key, () => entry); // Keep most recent (entries are sorted newest first)
    }

    // Build frequent foods list sorted by frequency
    final frequentList = frequencyMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // Sort by count descending

    final frequent = frequentList
        .map((e) => latestEntry[e.key]!)
        .toList();

    // Build recent foods list (first 50 unique)
    final seen = <String>{};
    final recent = <FoodEntry>[];
    for (final entry in entries) {
      if (!seen.contains(entry.name.toLowerCase())) {
        seen.add(entry.name.toLowerCase());
        recent.add(entry);
      }
      if (recent.length >= 50) break;
    }

    setState(() {
      _frequentFoods = frequent;
      _recentFoods = recent;
    });
  }

  Future<void> _loadMeals() async {
    final meals = await _storage.loadMeals();
    if (mounted) {
      setState(() {
        _savedMeals = meals;
      });
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });

    // Debounce API calls
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final results = await _foodSearch.search(query);
    if (mounted && _searchQuery == query) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

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

  void _addToSelection(String name, int calories, {
    double fat = 0,
    double carbs = 0,
    double protein = 0,
    double sugars = 0,
    String? portionAmount,
    bool? portionUseServing,
    Food? portionFood,
  }) {
    final entry = FoodEntry.create(
      name: name,
      calories: calories,
      fat: fat,
      carbs: carbs,
      protein: protein,
      sugars: sugars,
      mealType: widget.mealType,
      date: widget.date,
    );
    setState(() {
      _selectedEntries.add(entry);
      // Store portion info for editing later
      if (portionAmount != null && portionUseServing != null) {
        _portionInfo[entry.id] = (
          amount: portionAmount,
          useServing: portionUseServing,
          food: portionFood,
        );
      }
    });
  }

  void _removeFromSelection(int index) {
    setState(() {
      final entry = _selectedEntries[index];
      _portionInfo.remove(entry.id);
      _selectedEntries.removeAt(index);
    });
  }

  void _confirmSelection() {
    if (_selectedEntries.isEmpty) return;
    Navigator.of(context).pop(_selectedEntries);
  }

  int _getSelectionCount(String name) {
    return _selectedEntries.where((e) => e.name == name).length;
  }

  int get _totalSelectedCalories {
    return _selectedEntries.fold(0, (sum, e) => sum + e.calories);
  }

  void _addFoodFromSearch(Food food) {
    // Find existing entry to replace, if any
    final existingIndex = _selectedEntries.indexWhere((e) => e.name == food.displayName);
    final existingEntry = existingIndex >= 0 ? _selectedEntries[existingIndex] : null;
    _showPortionDialog(food, replaceIndex: existingIndex >= 0 ? existingIndex : null, existingEntryId: existingEntry?.id);
  }

  void _addFoodFromMyFoods(FoodEntry food) {
    // Find existing entry index to replace, if any
    final existingIndex = _selectedEntries.indexWhere((e) => e.name == food.name);
    _showEditMyFoodDialog(food, replaceIndex: existingIndex >= 0 ? existingIndex : null);
  }

  void _showEditMyFoodDialog(FoodEntry food, {int? replaceIndex}) {
    final caloriesController = TextEditingController(
      text: replaceIndex != null
          ? _selectedEntries[replaceIndex].calories.toString()
          : food.calories.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(food.name),
        content: TextField(
          controller: caloriesController,
          decoration: const InputDecoration(
            labelText: 'Calories',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
        ),
        actions: [
          if (replaceIndex != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeFromSelection(replaceIndex);
              },
              child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final calories = int.tryParse(caloriesController.text) ?? food.calories;
              Navigator.pop(context);

              // Calculate ratio to scale macros proportionally
              final ratio = calories / food.calories;

              if (replaceIndex != null) {
                _removeFromSelection(replaceIndex);
              }
              _addToSelection(
                food.name,
                calories,
                fat: food.fat * ratio,
                carbs: food.carbs * ratio,
                protein: food.protein * ratio,
                sugars: food.sugars * ratio,
              );
            },
            child: Text(replaceIndex != null ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _showPortionDialog(Food food, {int? replaceIndex, String? existingEntryId}) {
    final hasServing = food.servingSize != null && food.caloriesPerServing != null;

    // Get stored portion info if editing, or default to 1 serving if available
    String initialAmount = hasServing ? '1' : '';
    bool useServing = hasServing;
    double calculatedCalories = hasServing ? food.caloriesPerServing! : 0;
    double calculatedFat = hasServing ? (food.fatPerServing ?? food.fat100g) : 0;
    double calculatedCarbs = hasServing ? (food.carbsPerServing ?? food.carbs100g) : 0;
    double calculatedProtein = hasServing ? (food.proteinPerServing ?? food.protein100g) : 0;
    double calculatedSugars = hasServing ? (food.sugarsPerServing ?? food.sugars100g) : 0;

    if (existingEntryId != null && _portionInfo.containsKey(existingEntryId)) {
      // Restore saved portion info
      final info = _portionInfo[existingEntryId]!;
      initialAmount = info.amount;
      useServing = info.useServing;

      // Calculate values from stored amount
      final amount = double.tryParse(initialAmount) ?? 0;
      if (useServing) {
        calculatedCalories = (food.caloriesPerServing ?? food.calories100g) * amount;
        calculatedFat = (food.fatPerServing ?? food.fat100g) * amount;
        calculatedCarbs = (food.carbsPerServing ?? food.carbs100g) * amount;
        calculatedProtein = (food.proteinPerServing ?? food.protein100g) * amount;
        calculatedSugars = (food.sugarsPerServing ?? food.sugars100g) * amount;
      } else if (_useMetric) {
        calculatedCalories = food.calories100g * amount / 100;
        calculatedFat = food.fat100g * amount / 100;
        calculatedCarbs = food.carbs100g * amount / 100;
        calculatedProtein = food.protein100g * amount / 100;
        calculatedSugars = food.sugars100g * amount / 100;
      } else {
        calculatedCalories = (food.calories100g / 100 * _gramsPerOunce) * amount;
        calculatedFat = (food.fat100g / 100 * _gramsPerOunce) * amount;
        calculatedCarbs = (food.carbs100g / 100 * _gramsPerOunce) * amount;
        calculatedProtein = (food.protein100g / 100 * _gramsPerOunce) * amount;
        calculatedSugars = (food.sugars100g / 100 * _gramsPerOunce) * amount;
      }
    }

    final amountController = TextEditingController(text: initialAmount);

    // Unit labels based on metric/imperial
    final weightUnitLabel = _useMetric ? 'Grams' : 'Ounces';
    final weightUnitSuffix = _useMetric ? 'g' : 'oz';

    // Per weight unit (100g or 1oz)
    final caloriesPerWeightUnit = _useMetric
        ? food.calories100g
        : (food.calories100g / 100 * _gramsPerOunce);
    final fatPerWeightUnit = _useMetric ? food.fat100g : (food.fat100g / 100 * _gramsPerOunce);
    final carbsPerWeightUnit = _useMetric ? food.carbs100g : (food.carbs100g / 100 * _gramsPerOunce);
    final proteinPerWeightUnit = _useMetric ? food.protein100g : (food.protein100g / 100 * _gramsPerOunce);
    final sugarsPerWeightUnit = _useMetric ? food.sugars100g : (food.sugars100g / 100 * _gramsPerOunce);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void updateNutrition() {
            final amount = double.tryParse(amountController.text) ?? 0;
            setDialogState(() {
              if (useServing) {
                calculatedCalories = (food.caloriesPerServing ?? food.calories100g) * amount;
                calculatedFat = (food.fatPerServing ?? food.fat100g) * amount;
                calculatedCarbs = (food.carbsPerServing ?? food.carbs100g) * amount;
                calculatedProtein = (food.proteinPerServing ?? food.protein100g) * amount;
                calculatedSugars = (food.sugarsPerServing ?? food.sugars100g) * amount;
              } else if (_useMetric) {
                // Metric: amount in grams
                calculatedCalories = food.calories100g * amount / 100;
                calculatedFat = food.fat100g * amount / 100;
                calculatedCarbs = food.carbs100g * amount / 100;
                calculatedProtein = food.protein100g * amount / 100;
                calculatedSugars = food.sugars100g * amount / 100;
              } else {
                // Imperial: amount in ounces
                calculatedCalories = caloriesPerWeightUnit * amount;
                calculatedFat = fatPerWeightUnit * amount;
                calculatedCarbs = carbsPerWeightUnit * amount;
                calculatedProtein = proteinPerWeightUnit * amount;
                calculatedSugars = sugarsPerWeightUnit * amount;
              }
            });
          }

          void switchUnit(bool toServing) {
            setDialogState(() {
              useServing = toServing;
              amountController.text = '';
              updateNutrition();
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    Text(
                      food.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Unit toggle (if serving available)
                    if (hasServing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: true,
                              label: Text(food.servingSize!.split('(').first.trim()),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text(weightUnitLabel),
                            ),
                          ],
                          selected: {useServing},
                          onSelectionChanged: (selected) => switchUnit(selected.first),
                        ),
                      ),
                    // Amount input
                    TextField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: useServing ? 'Servings' : 'Amount',
                        suffixText: useServing ? null : weightUnitSuffix,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      autofocus: true,
                      onChanged: (_) => updateNutrition(),
                    ),
                    const SizedBox(height: 16),
                    // Calories display
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${calculatedCalories.round()}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'calories',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Macros display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildMacroChip('Fat', calculatedFat),
                        _buildMacroChip('Carbs', calculatedCarbs),
                        _buildMacroChip('Protein', calculatedProtein),
                        _buildMacroChip('Sugar', calculatedSugars),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Reference info
                    Text(
                      useServing && food.caloriesPerServing != null
                          ? '${food.caloriesPerServing!.round()} cal per ${food.servingSize}'
                          : _useMetric
                              ? '${food.calories100g.round()} cal per 100g'
                              : '${caloriesPerWeightUnit.round()} cal per oz',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Action buttons
                    Row(
                      children: [
                        if (replaceIndex != null)
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _removeFromSelection(replaceIndex);
                            },
                            child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            if (replaceIndex != null) {
                              _removeFromSelection(replaceIndex);
                            }
                            _addToSelection(
                              food.displayName,
                              calculatedCalories.round(),
                              fat: calculatedFat,
                              carbs: calculatedCarbs,
                              protein: calculatedProtein,
                              sugars: calculatedSugars,
                              portionAmount: amountController.text,
                              portionUseServing: useServing,
                              portionFood: food,
                            );
                          },
                          child: Text(replaceIndex != null ? 'Update' : 'Add'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMacroChip(String label, double value) {
    return Column(
      children: [
        Text(
          '${value.round()}g',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    final itemCount = _selectedEntries.length;
    final itemLabel = itemCount == 1 ? 'item' : 'items';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Clear button
          IconButton(
            onPressed: () => setState(() => _selectedEntries.clear()),
            icon: const Icon(Icons.close),
            tooltip: 'Clear selection',
            visualDensity: VisualDensity.compact,
          ),
          // Selection info
          Expanded(
            child: GestureDetector(
              onTap: _showSelectionDetails,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$itemCount $itemLabel selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$_totalSelectedCalories cal',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Add button
          FilledButton.icon(
            onPressed: _confirmSelection,
            icon: const Icon(Icons.check),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showSelectionDetails() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Selected Items',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _selectedEntries.clear());
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _selectedEntries.length,
                itemBuilder: (context, index) {
                  final entry = _selectedEntries[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${entry.calories} cal',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => _selectedEntries.removeAt(index));
                            if (_selectedEntries.isEmpty) {
                              Navigator.pop(context);
                            } else {
                              // Rebuild the bottom sheet
                              Navigator.pop(context);
                              _showSelectionDetails();
                            }
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                          color: Colors.red,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmSelection();
                },
                child: Text('Add ${_selectedEntries.length} items ($_totalSelectedCalories cal)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanBarcode() async {
    String? scannedBarcode;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Scan Barcode'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && scannedBarcode == null) {
                scannedBarcode = barcodes.first.rawValue;
                if (scannedBarcode != null) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ),
      ),
    );

    if (scannedBarcode == null || !mounted) return;

    // Look up the barcode
    final food = await _foodSearch.lookupBarcode(scannedBarcode!);

    if (!mounted) return;

    if (food != null) {
      _showPortionDialog(food);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product not found for barcode: $scannedBarcode'),
          action: SnackBarAction(
            label: 'Add manually',
            onPressed: () => _showManualEntryDialog(),
          ),
        ),
      );
    }
  }

  void _showManualEntryDialog({String? initialName}) {
    final nameController = TextEditingController(text: initialName ?? '');
    final caloriesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add Food',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Food name',
                      hintText: 'e.g., Apple, Chicken Salad',
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofocus: initialName == null,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a food name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: caloriesController,
                    decoration: const InputDecoration(
                      labelText: 'Calories',
                      hintText: 'e.g., 95',
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: initialName != null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter calories';
                      }
                      final calories = int.tryParse(value);
                      if (calories == null || calories <= 0) {
                        return 'Please enter a valid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.of(context).pop();
                            _addToSelection(
                              nameController.text.trim(),
                              int.parse(caloriesController.text),
                            );
                          }
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
        title: Text('Add to ${_mealName(widget.mealType)}'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for food...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSearching)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _scanBarcode,
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).colorScheme.outline,
              tabs: const [
                Tab(text: 'Frequent', height: 36),
                Tab(text: 'Recent', height: 36),
                Tab(text: 'Meals', height: 36),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFrequentTab(),
                _buildRecentTab(),
                _buildMealsTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _selectedEntries.isEmpty
              ? FilledButton(
                  onPressed: () => _showManualEntryDialog(),
                  child: const Text('Quick Calories'),
                )
              : _buildSelectionBar(),
        ),
      ),
    );
  }

  Widget _buildFrequentTab() {
    // When searching, show search results; otherwise show frequent foods
    if (_searchQuery.isNotEmpty) {
      // Show search results
      if (_isSearching && _searchResults.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_searchResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'No results for "$_searchQuery"',
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _showManualEntryDialog(initialName: _searchController.text),
                icon: const Icon(Icons.add),
                label: Text('Add "${_searchController.text}"'),
              ),
            ],
          ),
        );
      }

      // Search results list
      return ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final food = _searchResults[index];
          final displayCalories = _useMetric
              ? food.calories100g.round()
              : (food.calories100g / 100 * _gramsPerOunce).round();
          final displayUnit = _useMetric ? 'cal/100g' : 'cal/oz';
          final selectionCount = _getSelectionCount(food.displayName);

          return ListTile(
            title: Text(food.displayName),
            subtitle: food.brand != null ? Text(food.brand!) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$displayCalories $displayUnit',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
                if (selectionCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: selectionCount > 1
                        ? Text('$selectionCount',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                        : const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ],
              ],
            ),
            onTap: () => _addFoodFromSearch(food),
          );
        },
      );
    }

    // Show frequent foods (no search)
    if (_frequentFoods.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No foods logged yet',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your most frequent foods will appear here',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _frequentFoods.length,
      itemBuilder: (context, index) {
        final food = _frequentFoods[index];
        final selectionCount = _getSelectionCount(food.name);

        return ListTile(
          title: Text(food.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${food.calories} cal',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              if (selectionCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: selectionCount > 1
                      ? Text('$selectionCount',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                      : const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ],
            ],
          ),
          onTap: () => _addFoodFromMyFoods(food),
        );
      },
    );
  }

  Widget _buildRecentTab() {
    final filtered = _searchQuery.isEmpty
        ? _recentFoods
        : _recentFoods
            .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _searchQuery.isEmpty
                  ? 'No recent foods yet'
                  : 'No matching foods',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your last 50 foods will appear here',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final food = filtered[index];
        final selectionCount = _getSelectionCount(food.name);

        return ListTile(
          title: Text(food.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${food.calories} cal',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              if (selectionCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: selectionCount > 1
                      ? Text('$selectionCount',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                      : const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ],
            ],
          ),
          onTap: () => _addFoodFromMyFoods(food),
        );
      },
    );
  }

  Widget _buildMealsTab() {
    // Filter meals by current meal type
    final filtered = _savedMeals
        .where((meal) => meal.mealTypes.contains(widget.mealType))
        .where((meal) => _searchQuery.isEmpty ||
            meal.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _searchQuery.isEmpty
                  ? 'No saved meals for ${_mealName(widget.mealType).toLowerCase()}'
                  : 'No matching meals',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create meals from the log screen',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final meal = filtered[index];
        return ListTile(
          title: Text(meal.name),
          subtitle: Text(
            meal.items.map((item) => item.name).join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${meal.totalCalories} cal',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _showEditMealDialog(meal);
                  if (value == 'delete') _deleteMeal(meal);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          onTap: () => _addMeal(meal),
        );
      },
    );
  }

  void _addMeal(Meal meal) {
    // Create food entries for all items in the meal and add to selection
    for (final item in meal.items) {
      _addToSelection(
        item.name,
        item.calories,
        fat: item.fat,
        carbs: item.carbs,
        protein: item.protein,
        sugars: item.sugars,
      );
    }
  }

  Future<void> _deleteMeal(Meal meal) async {
    await _storage.deleteMeal(meal.id);
    _loadMeals();
  }

  Future<void> _showEditMealDialog(Meal meal) async {
    // Load existing meals to check for duplicate names
    final existingMeals = await _storage.loadMeals();
    final existingNames = existingMeals
        .where((m) => m.id != meal.id) // Exclude current meal
        .map((m) => m.name.toLowerCase())
        .toSet();

    final nameController = TextEditingController(text: meal.name);
    final selectedMealTypes = Set<MealType>.from(meal.mealTypes);
    String? errorText;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: const Text('Edit Meal'),
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
                  '${meal.items.length} items - ${meal.totalCalories} cal',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                ...meal.items.map((item) => Text(
                      '- ${item.name} (${item.calories} cal)',
                      style: const TextStyle(fontSize: 14),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = 'Please enter a name');
                  return;
                }
                if (existingNames.contains(name.toLowerCase())) {
                  setDialogState(() => errorText = 'A meal with this name already exists');
                  return;
                }
                Navigator.pop(context);
                // Create updated meal with same ID
                final updatedMeal = Meal(
                  id: meal.id,
                  name: name,
                  items: meal.items,
                  mealTypes: selectedMealTypes.toList(),
                );
                await _storage.saveMeal(updatedMeal);
                _loadMeals();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
