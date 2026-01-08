import 'package:flutter/material.dart';

import '../main.dart';
import '../services/storage_service.dart';

/// Settings screen for user preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();
  bool _useMetric = true;
  String _weekStart = 'monday'; // 'monday' or 'sunday'
  String _themeMode = 'system'; // 'system', 'light', 'dark'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
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
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
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
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
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
              ],
            ),
    );
  }
}
