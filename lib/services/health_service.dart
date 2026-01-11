import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for reading health data from Apple HealthKit (iOS) and Google Health Connect (Android).
///
/// Provides access to calorie burn data from fitness devices like Garmin, Apple Watch, etc.
class HealthService {
  final Health _health = Health();

  /// Health data types we need to read for calorie burn
  static const List<HealthDataType> _calorieTypes = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.BASAL_ENERGY_BURNED,
  ];

  /// Health data types for weight
  static const List<HealthDataType> _weightTypes = [
    HealthDataType.WEIGHT,
  ];

  /// All health data types we request permission for
  static List<HealthDataType> get _allTypes => [..._calorieTypes, ..._weightTypes];

  /// Permission levels for the data types
  /// Weight needs both READ and WRITE for Health Connect to work properly
  static List<HealthDataAccess> get _permissions {
    final permissions = <HealthDataAccess>[];
    // Calorie types: READ only
    for (var i = 0; i < _calorieTypes.length; i++) {
      permissions.add(HealthDataAccess.READ);
    }
    // Weight: READ_WRITE
    for (var i = 0; i < _weightTypes.length; i++) {
      permissions.add(HealthDataAccess.READ_WRITE);
    }
    return permissions;
  }

  /// Whether the service has been configured
  bool _isConfigured = false;

  /// Configures the health service. Call this once at app startup.
  Future<void> configure() async {
    if (_isConfigured) return;

    try {
      await _health.configure();
      _isConfigured = true;
    } catch (e) {
      debugPrint('HealthService: Failed to configure: $e');
    }
  }

  /// Checks if Health Connect is available on Android.
  /// Returns null on iOS (HealthKit is always available).
  Future<HealthConnectSdkStatus?> getHealthConnectStatus() async {
    if (!Platform.isAndroid) return null;

    try {
      return await _health.getHealthConnectSdkStatus();
    } catch (e) {
      debugPrint('HealthService: Failed to get Health Connect status: $e');
      return null;
    }
  }

  /// Checks if the user has granted health data permissions.
  Future<bool> hasPermissions() async {
    await configure();
    try {
      final result = await _health.hasPermissions(
        _allTypes,
        permissions: _permissions,
      );
      debugPrint('HealthService: hasPermissions result: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('HealthService: Failed to check permissions: $e');
      return false;
    }
  }

  /// Requests permission to read health data.
  ///
  /// On Android, also requests ACTIVITY_RECOGNITION permission.
  /// Returns true if permissions were granted.
  Future<bool> requestPermissions() async {
    await configure();

    try {
      // Android requires activity recognition permission
      if (Platform.isAndroid) {
        final activityStatus = await Permission.activityRecognition.request();
        if (!activityStatus.isGranted) {
          debugPrint('HealthService: Activity recognition permission denied');
        }
      }

      // Request health data permissions
      debugPrint('HealthService: Requesting authorization...');
      final authorized = await _health.requestAuthorization(
        _allTypes,
        permissions: _permissions,
      );
      debugPrint('HealthService: Authorization result: $authorized');

      return authorized;
    } catch (e) {
      debugPrint('HealthService: Failed to request permissions: $e');
      return false;
    }
  }

  /// Gets the total calories burned for a specific date.
  ///
  /// Returns a [CalorieBurnData] object with active and basal calories,
  /// or null if data could not be retrieved.
  Future<CalorieBurnData?> getCaloriesBurnedForDate(DateTime date) async {
    await configure();

    // Create date range for the entire day
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final healthData = await _health.getHealthDataFromTypes(
        types: _calorieTypes,
        startTime: startOfDay,
        endTime: endOfDay,
      );

      // Remove duplicates (same data from multiple sources)
      final uniqueData = _health.removeDuplicates(healthData);

      double activeCalories = 0;
      double basalCalories = 0;

      for (final point in uniqueData) {
        final value =
            (point.value as NumericHealthValue).numericValue.toDouble();

        if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          activeCalories += value;
        } else if (point.type == HealthDataType.BASAL_ENERGY_BURNED) {
          basalCalories += value;
        }
      }

      return CalorieBurnData(
        activeCalories: activeCalories.round(),
        basalCalories: basalCalories.round(),
        date: date,
      );
    } catch (e) {
      debugPrint('HealthService: Failed to get calories burned: $e');
      return null;
    }
  }

  /// Gets calories burned for today.
  Future<CalorieBurnData?> getTodayCaloriesBurned() async {
    return getCaloriesBurnedForDate(DateTime.now());
  }

  /// Gets calories burned for a date range.
  ///
  /// Returns a list of [CalorieBurnData] objects, one for each day in the range.
  /// Days with no data will have 0 calories.
  Future<List<CalorieBurnData>> getCaloriesBurnedForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    await configure();

    final results = <CalorieBurnData>[];

    // Normalize dates to start of day
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final endNormalized = DateTime(endDate.year, endDate.month, endDate.day);

    // Fetch data for each day in the range
    while (!currentDate.isAfter(endNormalized)) {
      final data = await getCaloriesBurnedForDate(currentDate);
      if (data != null) {
        results.add(data);
      } else {
        // Add zero-calorie entry for days with no data
        results.add(CalorieBurnData(
          activeCalories: 0,
          basalCalories: 0,
          date: currentDate,
        ));
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return results;
  }

  /// Syncs historical health data from a start date to today.
  ///
  /// [startDate] - The date to start syncing from (e.g., user signup date)
  /// [existingDates] - Set of date strings (YYYY-MM-DD) that already have data
  /// [forceRefreshDays] - Number of recent days to always refresh (default 2 for today/yesterday)
  ///
  /// Returns list of CalorieBurnData for dates that need saving.
  Future<List<CalorieBurnData>> syncHistoricalData({
    required DateTime startDate,
    required Set<String> existingDates,
    int forceRefreshDays = 2,
  }) async {
    await configure();

    final today = DateTime.now();
    final results = <CalorieBurnData>[];

    // Normalize start date
    var currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final todayNormalized = DateTime(today.year, today.month, today.day);

    // Don't sync future dates
    if (currentDate.isAfter(todayNormalized)) {
      return results;
    }

    debugPrint('HealthService: Syncing from ${_dateToId(currentDate)} to ${_dateToId(todayNormalized)}');

    while (!currentDate.isAfter(todayNormalized)) {
      final dateId = _dateToId(currentDate);
      final daysAgo = todayNormalized.difference(currentDate).inDays;

      // Check if we need to fetch this date
      final shouldFetch = !existingDates.contains(dateId) || daysAgo < forceRefreshDays;

      if (shouldFetch) {
        final data = await getCaloriesBurnedForDate(currentDate);
        if (data != null && (data.activeCalories > 0 || data.basalCalories > 0)) {
          results.add(data);
          debugPrint('HealthService: Got data for $dateId: ${data.activeCalories} active, ${data.basalCalories} basal');
        }
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    debugPrint('HealthService: Sync complete, fetched ${results.length} days with data');
    return results;
  }

  /// Formats a date as YYYY-MM-DD.
  String _dateToId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // ==================== Weight Data ====================

  /// Debug method to fetch all available health data for today
  Future<void> debugFetchAllData() async {
    await configure();

    final startTime = DateTime.now().subtract(const Duration(days: 365));
    final endTime = DateTime.now();

    debugPrint('HealthService DEBUG: Testing weight fetch...');

    try {
      // Request permission again just for weight (READ_WRITE needed per docs)
      final granted = await _health.requestAuthorization(
        [HealthDataType.WEIGHT],
        permissions: [HealthDataAccess.READ_WRITE],
      );
      debugPrint('HealthService DEBUG: Weight permission granted: $granted');

      // Try method 1: getHealthDataFromTypes
      debugPrint('HealthService DEBUG: Method 1 - getHealthDataFromTypes');
      final weightData1 = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: startTime,
        endTime: endTime,
      );
      debugPrint('HealthService DEBUG: Method 1 result: ${weightData1.length} entries');

      // Try method 2: Read BODY_MASS_INDEX instead
      debugPrint('HealthService DEBUG: Method 2 - trying BODY_MASS_INDEX');
      try {
        final bmiData = await _health.getHealthDataFromTypes(
          types: [HealthDataType.BODY_MASS_INDEX],
          startTime: startTime,
          endTime: endTime,
        );
        debugPrint('HealthService DEBUG: BMI result: ${bmiData.length} entries');
      } catch (e) {
        debugPrint('HealthService DEBUG: BMI failed: $e');
      }

      // Try method 3: Read multiple types at once including weight
      debugPrint('HealthService DEBUG: Method 3 - multiple types');
      final multiData = await _health.getHealthDataFromTypes(
        types: [
          HealthDataType.WEIGHT,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.STEPS,
        ],
        startTime: DateTime.now().subtract(const Duration(days: 7)),
        endTime: endTime,
      );
      debugPrint('HealthService DEBUG: Multi-type result: ${multiData.length} entries');
      for (final d in multiData) {
        debugPrint('HealthService DEBUG: Entry type=${d.type}, value=${d.value}, source=${d.sourceName}');
      }

    } catch (e, stack) {
      debugPrint('HealthService DEBUG: Error: $e');
      debugPrint('HealthService DEBUG: Stack: $stack');
    }
  }

  /// Gets weight entries from Health Connect for a date range.
  ///
  /// Returns a list of [WeightData] objects with weight and timestamp.
  Future<List<WeightData>> getWeightDataForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    await configure();

    final startNormalized = DateTime(startDate.year, startDate.month, startDate.day);
    // Use tomorrow to ensure we capture all of today's data regardless of timezone
    final tomorrow = endDate.add(const Duration(days: 1));
    final endNormalized = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);

    debugPrint('HealthService: Fetching weight from $startNormalized to $endNormalized');

    try {
      final healthData = await _health.getHealthDataFromTypes(
        types: _weightTypes,
        startTime: startNormalized,
        endTime: endNormalized,
      );

      debugPrint('HealthService: Raw weight data points: ${healthData.length}');
      for (final point in healthData) {
        debugPrint('HealthService: Raw point - type=${point.type}, value=${point.value}, source=${point.sourceName}, date=${point.dateFrom}');
      }

      // Remove duplicates
      final uniqueData = _health.removeDuplicates(healthData);
      debugPrint('HealthService: Unique weight data points: ${uniqueData.length}');

      final results = <WeightData>[];
      for (final point in uniqueData) {
        if (point.type == HealthDataType.WEIGHT) {
          final value = (point.value as NumericHealthValue).numericValue.toDouble();
          results.add(WeightData(
            weightKg: value,
            dateTime: point.dateFrom,
          ));
        }
      }

      // Sort by date ascending
      results.sort((a, b) => a.dateTime.compareTo(b.dateTime));

      debugPrint('HealthService: Parsed ${results.length} weight entries');
      return results;
    } catch (e) {
      debugPrint('HealthService: Failed to get weight data: $e');
      return [];
    }
  }

  /// Syncs weight data from Health Connect.
  ///
  /// [startDate] - The date to start syncing from
  /// [existingDates] - Set of date strings (YYYY-MM-DD) that already have weight data
  ///
  /// Returns list of WeightData for dates that need saving.
  Future<List<WeightData>> syncWeightData({
    required DateTime startDate,
    required Set<String> existingDates,
  }) async {
    await configure();

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);
    final startNormalized = DateTime(startDate.year, startDate.month, startDate.day);

    if (startNormalized.isAfter(todayNormalized)) {
      return [];
    }

    debugPrint('HealthService: Syncing weight from ${_dateToId(startNormalized)} to ${_dateToId(todayNormalized)}');

    final allWeightData = await getWeightDataForDateRange(startNormalized, todayNormalized);

    // Filter out dates we already have
    final newData = <WeightData>[];
    for (final data in allWeightData) {
      final dateId = _dateToId(data.dateTime);
      if (!existingDates.contains(dateId)) {
        newData.add(data);
        debugPrint('HealthService: New weight for $dateId: ${data.weightKg} kg');
      }
    }

    debugPrint('HealthService: Weight sync complete, found ${newData.length} new entries');
    return newData;
  }

  /// Revokes health permissions (Android only).
  Future<void> revokePermissions() async {
    try {
      await _health.revokePermissions();
    } catch (e) {
      debugPrint('HealthService: Failed to revoke permissions: $e');
    }
  }
}

/// Data class representing calorie burn for a specific date.
class CalorieBurnData {
  /// Calories burned through activity (exercise, walking, etc.)
  final int activeCalories;

  /// Calories burned at rest (basal metabolic rate)
  final int basalCalories;

  /// The date this data is for
  final DateTime date;

  const CalorieBurnData({
    required this.activeCalories,
    required this.basalCalories,
    required this.date,
  });

  /// Total calories burned (active + basal)
  int get totalCalories => activeCalories + basalCalories;

  @override
  String toString() {
    return 'CalorieBurnData(active: $activeCalories, basal: $basalCalories, total: $totalCalories)';
  }
}

/// Data class representing a weight measurement from Health Connect.
class WeightData {
  /// Weight in kilograms
  final double weightKg;

  /// When the weight was recorded
  final DateTime dateTime;

  const WeightData({
    required this.weightKg,
    required this.dateTime,
  });

  @override
  String toString() {
    return 'WeightData(weight: $weightKg kg, date: $dateTime)';
  }
}
