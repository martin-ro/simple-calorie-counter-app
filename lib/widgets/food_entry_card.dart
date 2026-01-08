import 'package:flutter/material.dart';

import '../models/food_entry.dart';

/// Displays a single food entry as a card in the list.
///
/// Shows the food name on the left, calories on the right,
/// and a delete button to remove the entry.
class FoodEntryCard extends StatelessWidget {
  /// The food entry to display
  final FoodEntry entry;

  /// Called when the user taps the delete button
  final VoidCallback onDelete;

  const FoodEntryCard({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        // Food name on the left
        title: Text(
          entry.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        // Calories on the right
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${entry.calories} cal',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
              tooltip: 'Delete entry',
            ),
          ],
        ),
      ),
    );
  }
}
