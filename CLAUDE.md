# Simple Calorie Tracker

A Flutter calorie tracking app with Firebase backend and Meilisearch for food search.

## Design Philosophy

- Keep the UI simple and clean
- Avoid using icons whenever possible - prefer text labels
- Use white backgrounds for dialogs and cards
- Follow Android Settings style:
  - Cards: minimal elevation (1), corner radius 24dp, white background, no border
  - NO dividers between items inside cards - use spacing only
  - List items: 16dp horizontal padding, separated by whitespace
- Modals/dialogs should be max width (use `insetPadding` and `SizedBox` with `MediaQuery`)
- No pill-shaped buttons or tabs - use rectangular shapes with subtle rounded corners (max `BorderRadius.circular(8)`)

## Tech Stack

- **Flutter** (Dart) - Mobile app framework
- **Firebase Auth** - User authentication
- **Cloud Firestore** - Database for user data (entries, profile, meals)
- **Meilisearch** - Food search engine (hosted at search.simple-calorie-tracker.com)
- **OpenFoodFacts** - Source of food/nutrition data

## Project Structure

```
lib/
├── main.dart              # App entry point, Firebase init, auth wrapper
├── models/
│   ├── food.dart          # Food item from search (OpenFoodFacts data)
│   └── food_entry.dart    # Logged food entry (what user ate)
├── screens/
│   ├── home_screen.dart   # Main screen with Log/Dashboard tabs, meal cards
│   ├── add_food_screen.dart   # Food search and portion selection
│   ├── login_screen.dart      # Login + forgot password
│   ├── onboarding_screen.dart # New user signup flow
│   └── settings_screen.dart   # User preferences (metric/imperial)
└── services/
    ├── auth_service.dart      # Firebase Auth wrapper
    ├── storage_service.dart   # Firestore operations
    └── food_search_service.dart # Meilisearch client
```

## Key Concepts

### Food vs FoodEntry
- `Food` - A searchable food item from the database (has calories_100g, serving_size, etc.)
- `FoodEntry` - A logged entry in the user's diary (has name, calories, mealType, dateTime)

### Meal Types
Four meal categories: `breakfast`, `lunch`, `dinner`, `snacks`

### Units
- User preference stored in profile as `useMetric` (bool)
- Metric: grams, kg, cm
- Imperial: ounces, lb, ft
- Conversion: 1 oz = 28.3495g

## External Services

### Meilisearch
- Host: `https://search.simple-calorie-tracker.com`
- Index: `testing` (use `production` for prod)
- API key in `food_search_service.dart`

### Firebase
- Project configured via `firebase_options.dart`
- Firestore collections:
  - `users/{userId}/entries` - Food diary entries
  - `users/{userId}/profile` - User profile and preferences

### Email (Password Reset)
- SMTP via Resend (configured in Firebase Console)
- Sender: noreply@simple-calorie-tracker.com

## Scripts

```bash
# Import test food data to Meilisearch
cd scripts && node import_test_data.js
```

The import script reads from `scripts/openfoodfacts_data.json` (static OpenFoodFacts API response).

## Data Parsing Notes

Food data from Meilisearch may have numeric fields as strings. The `Food.fromJson` uses `_parseDouble()` helper to handle both:
```dart
static double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
```

## Common Patterns

### Loading user preferences
```dart
final profile = await _storage.loadProfile();
final useMetric = profile?['useMetric'] as bool? ?? true;
```

### Date filtering for entries
```dart
_entries.where((entry) =>
  entry.dateTime.year == date.year &&
  entry.dateTime.month == date.month &&
  entry.dateTime.day == date.day
).toList();
```

### Dialog styling
Dialogs use white background and near-full width:
```dart
AlertDialog(
  backgroundColor: Colors.white,
  insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  content: SizedBox(
    width: MediaQuery.of(context).size.width,
    child: ...
  ),
)
```

## Running the App

```bash
flutter pub get
flutter run
```

## TODO / Incomplete Features

- Meal saving/storage (model and Firestore collection needed)
- Barcode scanning
- Dashboard analytics
- Profile editing screen
