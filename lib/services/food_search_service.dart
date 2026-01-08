import 'package:meilisearch/meilisearch.dart';

import '../models/food.dart';

/// Service for searching foods using Meilisearch.
///
/// Uses the OpenFoodFacts data imported into our Meilisearch instance.
class FoodSearchService {
  static const String _host = 'https://search.simple-calorie-tracker.com';
  // TODO: Replace with actual search-only API key
  static const String _apiKey = 'e6f4c9a7b1d84e3fa2c0e9b5f7a1d6c8e3b9a4f2d7c5e1a0b6f8c9d2e4a7';
  static const String _indexName = 'testing'; // Use 'production' for prod builds

  final MeiliSearchClient _client;

  FoodSearchService()
      : _client = MeiliSearchClient(_host, _apiKey);

  /// Search foods by name or brand
  /// If query is empty, returns all foods (up to limit)
  Future<List<Food>> search(String query, {int limit = 20}) async {
    print('SEARCH: query="$query", limit=$limit');
    try {
      final index = _client.index(_indexName);

      // For empty queries, fetch documents directly
      if (query.trim().isEmpty) {
        print('SEARCH: Using getDocuments for empty query');
        final result = await index.getDocuments(
          params: DocumentsQuery(limit: limit),
        );
        print('SEARCH: getDocuments returned ${result.results.length} items');
        return result.results
            .map((doc) => Food.fromJson(doc as Map<String, dynamic>))
            .toList();
      }

      // For actual searches, use search API
      print('SEARCH: Using search API');
      final result = await index.search(
        query,
        SearchQuery(limit: limit),
      );
      print('SEARCH: search returned ${result.hits.length} hits');
      return result.hits
          .map((hit) => Food.fromJson(hit as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      // Return empty list on error (e.g., network issues)
      print('SEARCH ERROR: $e');
      print('SEARCH STACK: $stack');
      return [];
    }
  }

  /// Lookup food by exact barcode
  Future<Food?> lookupBarcode(String barcode) async {
    if (barcode.trim().isEmpty) {
      return null;
    }

    try {
      final index = _client.index(_indexName);
      final result = await index.search(
        barcode,
        SearchQuery(
          limit: 1,
          filter: 'id = "$barcode"',
        ),
      );
      if (result.hits.isEmpty) {
        return null;
      }
      return Food.fromJson(result.hits.first as Map<String, dynamic>);
    } catch (e) {
      print('Meilisearch barcode lookup error: $e');
      return null;
    }
  }
}
