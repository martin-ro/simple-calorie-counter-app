import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../main.dart';
import '../services/health_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_card.dart';

/// Settings screen for user preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();
  final _healthService = HealthService();
  bool _useMetric = true;
  String _weekStart = 'monday'; // 'monday' or 'sunday'
  String _themeMode = 'system'; // 'system', 'light', 'dark'
  bool _isLoading = true;
  bool _healthConnected = false;
  bool _healthAvailable = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkHealthStatus();
  }

  Future<void> _checkHealthStatus() async {
    // Check if Health Connect is available on Android
    if (Platform.isAndroid) {
      final status = await _healthService.getHealthConnectStatus();
      debugPrint('SettingsScreen: Health Connect status: $status');
      // Only mark as unavailable if we explicitly know it's not available
      if (status == HealthConnectSdkStatus.sdkUnavailable ||
          status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
        setState(() {
          _healthAvailable = false;
        });
        return;
      }
    }

    final hasPermissions = await _healthService.hasPermissions();
    debugPrint('SettingsScreen: Has permissions: $hasPermissions');
    setState(() {
      _healthConnected = hasPermissions;
    });
  }

  Future<void> _toggleHealthConnection() async {
    debugPrint('SettingsScreen: Toggle called, currently connected: $_healthConnected');
    if (_healthConnected) {
      // Disconnect - revoke permissions
      await _healthService.revokePermissions();
      setState(() {
        _healthConnected = false;
      });
    } else {
      // Connect - request permissions
      debugPrint('SettingsScreen: Requesting permissions...');
      await _healthService.requestPermissions();
      // Re-check permissions after user interaction
      debugPrint('SettingsScreen: Re-checking permissions...');
      final hasPermissions = await _healthService.hasPermissions();
      debugPrint('SettingsScreen: After request, has permissions: $hasPermissions');

      // Store the connection date for historical sync
      if (hasPermissions) {
        final profile = await _storage.loadProfile() ?? {};
        if (profile['healthConnectedDate'] == null) {
          profile['healthConnectedDate'] = DateTime.now().toIso8601String();
          await _storage.saveProfile(profile);
          debugPrint('SettingsScreen: Stored healthConnectedDate');
        }
      }

      setState(() {
        _healthConnected = hasPermissions;
      });
    }
  }

  Future<void> _loadSettings() async {
    final profile = await _storage.loadProfile();
    if (mounted) {
      setState(() {
        _useMetric = profile?['useMetric'] as bool? ?? true;
        _weekStart = profile?['weekStart'] as String? ?? 'monday';
        _themeMode = profile?['themeMode'] as String? ?? 'system';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final profile = await _storage.loadProfile() ?? {};
    profile['useMetric'] = _useMetric;
    profile['weekStart'] = _weekStart;
    profile['themeMode'] = _themeMode;
    await _storage.saveProfile(profile);
  }

  void _setThemeMode(String mode) {
    setState(() {
      _themeMode = mode;
    });
    _saveSettings();
    // Update global theme notifier for immediate effect
    switch (mode) {
      case 'light':
        themeNotifier.value = ThemeMode.light;
      case 'dark':
        themeNotifier.value = ThemeMode.dark;
      default:
        themeNotifier.value = ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Units',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                AppCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        title: const Text('Metric'),
                        subtitle: const Text('grams, kilograms, centimeters'),
                        value: true,
                        groupValue: _useMetric,
                        onChanged: (value) {
                          setState(() {
                            _useMetric = value!;
                          });
                          _saveSettings();
                        },
                      ),
                      const Divider(height: 1),
                      RadioListTile<bool>(
                        title: const Text('Imperial'),
                        subtitle: const Text('ounces, pounds, feet'),
                        value: false,
                        groupValue: _useMetric,
                        onChanged: (value) {
                          setState(() {
                            _useMetric = value!;
                          });
                          _saveSettings();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Week Start',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                AppCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text('Monday'),
                        value: 'monday',
                        groupValue: _weekStart,
                        onChanged: (value) {
                          setState(() {
                            _weekStart = value!;
                          });
                          _saveSettings();
                        },
                      ),
                      const Divider(height: 1),
                      RadioListTile<String>(
                        title: const Text('Sunday'),
                        value: 'sunday',
                        groupValue: _weekStart,
                        onChanged: (value) {
                          setState(() {
                            _weekStart = value!;
                          });
                          _saveSettings();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                AppCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text('System'),
                        subtitle: const Text('Follow device settings'),
                        value: 'system',
                        groupValue: _themeMode,
                        onChanged: (value) => _setThemeMode(value!),
                      ),
                      const Divider(height: 1),
                      RadioListTile<String>(
                        title: const Text('Light'),
                        value: 'light',
                        groupValue: _themeMode,
                        onChanged: (value) => _setThemeMode(value!),
                      ),
                      const Divider(height: 1),
                      RadioListTile<String>(
                        title: const Text('Dark'),
                        value: 'dark',
                        groupValue: _themeMode,
                        onChanged: (value) => _setThemeMode(value!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Health Data',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                AppCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: SwitchListTile(
                    title: Text(
                      Platform.isIOS ? 'Apple Health' : 'Health Connect',
                    ),
                    subtitle: Text(
                      _healthAvailable
                          ? (_healthConnected
                              ? 'Connected - syncing exercise calories'
                              : 'Connect to import exercise calories')
                          : 'Health Connect app not installed',
                    ),
                    value: _healthConnected,
                    onChanged: _healthAvailable
                        ? (value) => _toggleHealthConnection()
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
