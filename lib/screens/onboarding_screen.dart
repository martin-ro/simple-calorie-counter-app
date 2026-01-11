import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'register_screen.dart';

/// Multi-step onboarding flow.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentPage = 0;

  // Form keys
  final _weightFormKey = GlobalKey<FormState>();
  final _targetWeightFormKey = GlobalKey<FormState>();
  final _heightFormKey = GlobalKey<FormState>();

  // Form data
  String? _gender;
  String? _genderError;
  String? _activityLevel;
  String? _activityLevelError;
  final _weightController = TextEditingController();
  String _weightUnit = 'lb';
  final _targetWeightController = TextEditingController();
  final _heightController = TextEditingController();
  String _heightUnit = 'ft';
  DateTime? _birthday;

  @override
  void dispose() {
    _weightController.dispose();
    _targetWeightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 6) {
      setState(() {
        _currentPage++;
      });
    }
  }

  void _skip() {
    _nextPage();
  }

  void _goToRegistration() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RegisterScreen(
          profileData: {
            'gender': _gender,
            'weight': double.tryParse(_weightController.text),
            'weightUnit': _weightUnit,
            'targetWeight': double.tryParse(_targetWeightController.text),
            'height': double.tryParse(_heightController.text),
            'heightUnit': _heightUnit,
            'birthday': _birthday?.toIso8601String(),
            'activityLevel': _activityLevel,
            'calorieBudget': _calorieBudget,
            'useMetric': _weightUnit == 'kg',
          },
        ),
      ),
    );
  }

  double? get _weightToLose {
    final current = double.tryParse(_weightController.text);
    final target = double.tryParse(_targetWeightController.text);
    if (current != null && target != null) {
      return current - target;
    }
    return null;
  }

  int? get _age {
    if (_birthday == null) return null;
    final now = DateTime.now();
    int age = now.year - _birthday!.year;
    if (now.month < _birthday!.month ||
        (now.month == _birthday!.month && now.day < _birthday!.day)) {
      age--;
    }
    return age;
  }

  double? get _weightInKg {
    final weight = double.tryParse(_weightController.text);
    if (weight == null) return null;
    switch (_weightUnit) {
      case 'kg':
        return weight;
      case 'lb':
        return weight * 0.453592;
      case 'st':
        return weight * 6.35029;
      default:
        return weight;
    }
  }

  double? get _heightInCm {
    final height = double.tryParse(_heightController.text);
    if (height == null) return null;
    switch (_heightUnit) {
      case 'cm':
        return height;
      case 'ft':
        return height * 30.48;
      default:
        return height;
    }
  }

  double get _activityMultiplier {
    switch (_activityLevel) {
      case 'sedentary':
        return 1.2;
      case 'light':
        return 1.375;
      case 'moderate':
        return 1.55;
      case 'active':
        return 1.725;
      case 'very_active':
        return 1.9;
      default:
        return 1.2;
    }
  }

  int? get _calorieBudget {
    final weightKg = _weightInKg;
    final heightCm = _heightInCm;
    final age = _age;
    if (weightKg == null || heightCm == null || age == null || _gender == null || _activityLevel == null) {
      return null;
    }

    // Mifflin-St Jeor equation for BMR
    double bmr;
    if (_gender == 'male') {
      bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + 5;
    } else {
      bmr = 10 * weightKg + 6.25 * heightCm - 5 * age - 161;
    }

    // Apply activity multiplier for TDEE
    double tdee = bmr * _activityMultiplier;

    // Subtract 500 calories for weight loss (~1 lb/week)
    final weightToLose = _weightToLose;
    if (weightToLose != null && weightToLose > 0) {
      tdee -= 500;
    }

    // Ensure minimum healthy intake
    final minCalories = _gender == 'male' ? 1500 : 1200;
    return tdee.round().clamp(minCalories, 10000);
  }

  void _previousPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _previousPage,
        ),
        title: LinearProgressIndicator(
          value: (_currentPage + 1) / 7,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        titleSpacing: 0,
      ),
      body: IndexedStack(
        index: _currentPage,
        children: [
          _buildWeightPage(),
          _buildTargetWeightPage(),
          _buildGenderPage(),
          _buildHeightPage(),
          _buildActivityLevelPage(),
          _buildBirthdayPage(),
          _buildSuccessPage(),
        ],
      ),
    );
  }

  Widget _buildPageLayout({
    required String title,
    String? subtitle,
    required Widget content,
    required VoidCallback onContinue,
    bool showSkip = false,
    String continueText = 'Continue',
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                content,
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: onContinue,
                  child: Text(continueText),
                ),
                if (showSkip) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _skip,
                    child: const Text('Skip'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderPage() {
    return _buildPageLayout(
      title: 'What\'s your gender?',
      showSkip: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGenderOption('male', 'Male'),
          const SizedBox(height: 12),
          _buildGenderOption('female', 'Female'),
          const SizedBox(height: 12),
          _buildGenderOption('other', 'Other'),
          if (_genderError != null) ...[
            const SizedBox(height: 8),
            Text(
              _genderError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      onContinue: () {
        if (_gender == null) {
          setState(() {
            _genderError = 'Please select your gender';
          });
          return;
        }
        _nextPage();
      },
    );
  }

  Widget _buildGenderOption(String value, String label) {
    final isSelected = _gender == value;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _gender = value;
            _genderError = null;
          });
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _buildWeightPage() {
    return _buildPageLayout(
      title: 'What\'s your current weight?',
      showSkip: false,
      content: Form(
        key: _weightFormKey,
        child: TextFormField(
          controller: _weightController,
          decoration: InputDecoration(
            labelText: 'Current Weight',
            border: const OutlineInputBorder(),
            suffixIcon: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _weightUnit,
                padding: const EdgeInsets.only(right: 8),
                items: const [
                  DropdownMenuItem(value: 'kg', child: Text('kg')),
                  DropdownMenuItem(value: 'lb', child: Text('lb')),
                  DropdownMenuItem(value: 'st', child: Text('st')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _weightUnit = value;
                    });
                  }
                },
              ),
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your current weight';
            }
            return null;
          },
        ),
      ),
      onContinue: () {
        if (_weightFormKey.currentState!.validate()) {
          _nextPage();
        }
      },
    );
  }

  Widget _buildTargetWeightPage() {
    return _buildPageLayout(
      title: 'What\'s your target weight?',
      showSkip: false,
      content: Form(
        key: _targetWeightFormKey,
        child: TextFormField(
          controller: _targetWeightController,
          decoration: InputDecoration(
            labelText: 'Target Weight',
            border: const OutlineInputBorder(),
            suffixIcon: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _weightUnit,
                padding: const EdgeInsets.only(right: 8),
                items: const [
                  DropdownMenuItem(value: 'kg', child: Text('kg')),
                  DropdownMenuItem(value: 'lb', child: Text('lb')),
                  DropdownMenuItem(value: 'st', child: Text('st')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _weightUnit = value;
                    });
                  }
                },
              ),
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your target weight';
            }
            return null;
          },
        ),
      ),
      onContinue: () {
        if (_targetWeightFormKey.currentState!.validate()) {
          _nextPage();
        }
      },
    );
  }

  Widget _buildHeightPage() {
    return _buildPageLayout(
      title: 'What\'s your height?',
      showSkip: false,
      content: Form(
        key: _heightFormKey,
        child: TextFormField(
          controller: _heightController,
          decoration: InputDecoration(
            labelText: 'Height',
            border: const OutlineInputBorder(),
            suffixIcon: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _heightUnit,
                padding: const EdgeInsets.only(right: 8),
                items: const [
                  DropdownMenuItem(value: 'cm', child: Text('cm')),
                  DropdownMenuItem(value: 'ft', child: Text('ft')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _heightUnit = value;
                    });
                  }
                },
              ),
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your height';
            }
            return null;
          },
        ),
      ),
      onContinue: () {
        if (_heightFormKey.currentState!.validate()) {
          _nextPage();
        }
      },
    );
  }

  Widget _buildActivityLevelPage() {
    return _buildPageLayout(
      title: 'How active are you?',
      showSkip: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildActivityOption('sedentary', 'Sedentary', 'Little or no exercise'),
          const SizedBox(height: 12),
          _buildActivityOption('light', 'Lightly Active', 'Light exercise 1-3 days/week'),
          const SizedBox(height: 12),
          _buildActivityOption('moderate', 'Moderately Active', 'Moderate exercise 3-5 days/week'),
          const SizedBox(height: 12),
          _buildActivityOption('active', 'Very Active', 'Hard exercise 6-7 days/week'),
          const SizedBox(height: 12),
          _buildActivityOption('very_active', 'Extra Active', 'Very hard exercise & physical job'),
          if (_activityLevelError != null) ...[
            const SizedBox(height: 8),
            Text(
              _activityLevelError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      onContinue: () {
        if (_activityLevel == null) {
          setState(() {
            _activityLevelError = 'Please select your activity level';
          });
          return;
        }
        _nextPage();
      },
    );
  }

  Widget _buildActivityOption(String value, String label, String description) {
    final isSelected = _activityLevel == value;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _activityLevel = value;
            _activityLevelError = null;
          });
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(label),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayPage() {
    return _buildPageLayout(
      title: 'When were you born?',
      showSkip: false,
      content: SizedBox(
        height: 200,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: _birthday ?? DateTime(DateTime.now().year - 25),
          minimumDate: DateTime(1900),
          maximumDate: DateTime.now(),
          onDateTimeChanged: (date) {
            setState(() {
              _birthday = date;
            });
          },
        ),
      ),
      onContinue: () {
        _birthday ??= DateTime(DateTime.now().year - 25);
        _nextPage();
      },
    );
  }

  Widget _buildSuccessPage() {
    final weightToLose = _weightToLose;
    final hasWeightGoal = weightToLose != null && weightToLose > 0;

    return _buildPageLayout(
      title: 'You\'re all set!',
      subtitle: 'Here\'s your profile summary',
      content: Column(
        children: [
          if (_calorieBudget != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    '$_calorieBudget kcal',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'daily calorie budget',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (hasWeightGoal) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    '${weightToLose.toStringAsFixed(1)} $_weightUnit',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'to reach your goal',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_weightController.text.isNotEmpty)
            _buildSummaryRow('Current Weight', '${_weightController.text} $_weightUnit'),
          if (_targetWeightController.text.isNotEmpty)
            _buildSummaryRow('Target Weight', '${_targetWeightController.text} $_weightUnit'),
          if (_gender != null) _buildSummaryRow('Gender', _gender!),
          if (_heightController.text.isNotEmpty)
            _buildSummaryRow('Height', '${_heightController.text} $_heightUnit'),
          if (_age != null)
            _buildSummaryRow('Age', '$_age'),
        ],
      ),
      onContinue: _goToRegistration,
      continueText: 'Create Account',
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
