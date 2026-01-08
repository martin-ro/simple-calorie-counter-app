#!/usr/bin/env node

/**
 * Import foods from local OpenFoodFacts data file into Meilisearch
 */

import { MeiliSearch } from 'meilisearch';
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const MEILISEARCH_HOST = process.env.MEILISEARCH_HOST || 'https://search.simple-calorie-tracker.com';
const MEILISEARCH_API_KEY = process.env.MEILISEARCH_API_KEY || 'e6f4c9a7b1d84e3fa2c0e9b5f7a1d6c8e3b9a4f2d7c5e1a0b6f8c9d2e4a7';
const INDEX_NAME = 'testing';

async function main() {
  console.log('Loading foods from local file...\n');

  // Read local data file
  const dataPath = join(__dirname, 'openfoodfacts_data.json');
  const rawData = JSON.parse(readFileSync(dataPath, 'utf-8'));

  // Transform to our format
  const foods = rawData.products
    .filter(p =>
      p.product_name &&
      p.code &&
      p.nutriments?.['energy-kcal_100g'] != null
    )
    .slice(0, 100) // Limit to 100
    .map(p => {
      const n = p.nutriments || {};
      const servingQty = p.serving_quantity || null;
      return {
        id: p.code,
        name: p.product_name.substring(0, 200),
        brand: p.brands?.substring(0, 100) || null,
        // Calories
        calories_100g: Math.round(n['energy-kcal_100g'] || 0),
        calories_serving: servingQty && n['energy-kcal_100g']
          ? Math.round((n['energy-kcal_100g'] / 100) * servingQty)
          : null,
        // Macros per 100g
        fat_100g: n.fat_100g || 0,
        carbs_100g: n.carbohydrates_100g || 0,
        protein_100g: n.proteins_100g || 0,
        sugars_100g: n.sugars_100g || 0,
        // Macros per serving
        fat_serving: servingQty ? (n.fat_100g || 0) / 100 * servingQty : null,
        carbs_serving: servingQty ? (n.carbohydrates_100g || 0) / 100 * servingQty : null,
        protein_serving: servingQty ? (n.proteins_100g || 0) / 100 * servingQty : null,
        sugars_serving: servingQty ? (n.sugars_100g || 0) / 100 * servingQty : null,
        // Serving info
        serving_size: p.serving_size || null,
        serving_grams: servingQty,
        categories: []
      };
    });

  console.log(`Loaded ${foods.length} foods from file\n`);

  // Import to Meilisearch
  console.log(`Importing to Meilisearch...`);
  console.log(`Host: ${MEILISEARCH_HOST}`);

  const client = new MeiliSearch({
    host: MEILISEARCH_HOST,
    apiKey: MEILISEARCH_API_KEY,
  });

  try {
    const health = await client.health();
    console.log(`Status: ${health.status}\n`);

    const index = client.index(INDEX_NAME);

    console.log('Clearing existing data...');
    await index.deleteAllDocuments();
    await new Promise(r => setTimeout(r, 1000));

    console.log('Configuring index...');
    await index.updateSearchableAttributes(['name', 'brand', 'id']);
    await index.updateFilterableAttributes(['id', 'categories']);
    await index.updateSortableAttributes(['calories_100g']);

    console.log(`Adding ${foods.length} foods...`);
    const task = await index.addDocuments(foods);

    await client.waitForTask(task.taskUid);

    const stats = await index.getStats();
    console.log(`\nDone! ${stats.numberOfDocuments} foods indexed.`);

    console.log('\nSample foods imported:');
    foods.slice(0, 10).forEach(f => {
      console.log(`  - ${f.name}${f.brand ? ` (${f.brand})` : ''}: ${f.calories_100g} cal/100g, serving: ${f.serving_size || 'N/A'}`);
    });

  } catch (error) {
    console.error('Meilisearch error:', error.message);
    process.exit(1);
  }
}

main();
