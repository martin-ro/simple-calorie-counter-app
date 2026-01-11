import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/food_entry.dart';

/// A dialog for adding a new food entry.
///
/// Contains text fields for food name and calories.
/// Returns a FoodEntry if the user submits valid data, or null if cancelled.
class AddFoodDialog extends StatefulWidget {
  final MealType mealType;

  const AddFoodDialog({super.key, required this.mealType});

  @override
  State<AddFoodDialog> createState() => _AddFoodDialogState();
}

class _AddFoodDialogState extends State<AddFoodDialog> {
  // Controllers to read the text field values
  final _nameController = TextEditingController();
  final _caloriesController = TextEditingController();

  // Key for form validation
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    // Clean up controllers when the dialog is closed
    _nameController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  /// Validates input and returns the new entry if valid
  void _submit() {
    // Check if form is valid
    if (_formKey.currentState!.validate()) {
      // Create a new entry with the input values
      final entry = FoodEntry.create(
        name: _nameController.text.trim(),
        calories: int.parse(_caloriesController.text),
        mealType: widget.mealType,
      );

      // Return the entry to the caller
      Navigator.of(context).pop(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Food'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Food name input
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Food name',
                hintText: 'e.g., Apple, Chicken Salad',
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a food name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Calories input
            TextFormField(
              controller: _caloriesController,
              decoration: const InputDecoration(
                labelText: 'Calories',
                hintText: 'e.g., 95',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                // Only allow digits
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
          ],
        ),
      ),
      actions: [
        // Cancel button
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        // Add button
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
