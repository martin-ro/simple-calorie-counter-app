#!/usr/bin/env node

/**
 * OpenFoodFacts to Meilisearch Import Script
 *
 * Downloads the OpenFoodFacts data dump and imports it into Meilisearch.
 *
 * Usage:
 *   npm run import        # Import with default settings
 *   npm run import:full   # Full import (no limit)
 *
 * Environment variables:
 *   MEILISEARCH_HOST      # Meilisearch host URL (default: https://search.simple-calorie-tracker.com)
 *   MEILISEARCH_API_KEY   # Meilisearch master key
 */

import { createReadStream, createWriteStream, existsSync, unlinkSync } from 'fs';
import { createInterface } from 'readline';
import { pipeline } from 'stream/promises';
import { createGunzip } from 'zlib';
import { MeiliSearch } from 'meilisearch';

// Configuration
const MEILISEARCH_HOST = process.env.MEILISEARCH_HOST || 'https://search.simple-calorie-tracker.com';
const MEILISEARCH_API_KEY = process.env.MEILISEARCH_API_KEY || 'e6f4c9a7b1d84e3fa2c0e9b5f7a1d6c8e3b9a4f2d7c5e1a0b6f8c9d2e4a7';
const INDEX_NAME = process.env.INDEX_NAME || 'production';

// OpenFoodFacts data dump URL (JSONL format, gzipped)
const DATA_URL = 'https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz';
const LOCAL_FILE = 'openfoodfacts-products.jsonl.gz';
const EXTRACTED_FILE = 'openfoodfacts-products.jsonl';

// Import settings
const BATCH_SIZE = 10000;
const MAX_PRODUCTS = process.argv.includes('--full') ? Infinity : 500000; // Default 500k for faster imports

// Initialize Meilisearch client
const client = new MeiliSearch({
  host: MEILISEARCH_HOST,
  apiKey: MEILISEARCH_API_KEY,
});

/**
 * Download file with progress
 */
async function downloadFile(url, destination) {
  console.log(`Downloading from ${url}...`);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download: ${response.status} ${response.statusText}`);
  }

  const totalSize = parseInt(response.headers.get('content-length') || '0', 10);
  let downloadedSize = 0;
  let lastProgress = 0;

  const fileStream = createWriteStream(destination);
  const reader = response.body.getReader();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    fileStream.write(Buffer.from(value));
    downloadedSize += value.length;

    if (totalSize > 0) {
      const progress = Math.floor((downloadedSize / totalSize) * 100);
      if (progress !== lastProgress && progress % 5 === 0) {
        console.log(`  Download progress: ${progress}% (${(downloadedSize / 1e9).toFixed(2)} GB)`);
        lastProgress = progress;
      }
    }
  }

  fileStream.end();
  console.log(`  Download complete: ${(downloadedSize / 1e9).toFixed(2)} GB`);
}

/**
 * Extract gzipped file
 */
async function extractFile(source, destination) {
  console.log(`Extracting ${source}...`);

  await pipeline(
    createReadStream(source),
    createGunzip(),
    createWriteStream(destination)
  );

  console.log('  Extraction complete');
}

/**
 * Transform OpenFoodFacts product to our Meilisearch format
 */
function transformProduct(product) {
  // Skip products without essential data
  if (!product.code || !product.product_name) {
    return null;
  }

  // Get calories - try different field names
  const calories =
    product.nutriments?.['energy-kcal_100g'] ||
    product.nutriments?.['energy_100g'] / 4.184 || // Convert kJ to kcal
    0;

  // Skip if no calorie data
  if (!calories || calories <= 0) {
    return null;
  }

  // Get serving data
  const servingSize = product.serving_size || null;
  const servingGrams = product.serving_quantity || null;
  const caloriesServing =
    product.nutriments?.['energy-kcal_serving'] ||
    (product.nutriments?.['energy_serving'] ? product.nutriments['energy_serving'] / 4.184 : null) ||
    null;

  return {
    id: product.code,
    name: product.product_name.trim(),
    brand: product.brands?.split(',')[0]?.trim() || null,
    calories_100g: Math.round(calories * 10) / 10, // Round to 1 decimal
    serving_size: servingSize,
    serving_grams: servingGrams ? Math.round(servingGrams * 10) / 10 : null,
    calories_serving: caloriesServing ? Math.round(caloriesServing * 10) / 10 : null,
    categories: product.categories_tags?.slice(0, 5) || [], // Limit categories
  };
}

/**
 * Process JSONL file and upload to Meilisearch in batches
 */
async function importToMeilisearch(filePath) {
  console.log(`\nImporting to Meilisearch (max ${MAX_PRODUCTS === Infinity ? 'unlimited' : MAX_PRODUCTS} products)...`);

  const fileStream = createReadStream(filePath);
  const rl = createInterface({
    input: fileStream,
    crlfDelay: Infinity,
  });

  let batch = [];
  let totalProcessed = 0;
  let totalImported = 0;
  let totalSkipped = 0;

  const index = client.index(INDEX_NAME);

  for await (const line of rl) {
    if (totalImported >= MAX_PRODUCTS) {
      break;
    }

    totalProcessed++;

    try {
      const product = JSON.parse(line);
      const transformed = transformProduct(product);

      if (transformed) {
        batch.push(transformed);

        if (batch.length >= BATCH_SIZE) {
          await index.addDocuments(batch);
          totalImported += batch.length;
          console.log(`  Imported ${totalImported.toLocaleString()} products (processed ${totalProcessed.toLocaleString()}, skipped ${totalSkipped.toLocaleString()})`);
          batch = [];
        }
      } else {
        totalSkipped++;
      }
    } catch (e) {
      totalSkipped++;
    }
  }

  // Upload remaining batch
  if (batch.length > 0) {
    await index.addDocuments(batch);
    totalImported += batch.length;
  }

  console.log(`\nImport complete!`);
  console.log(`  Total processed: ${totalProcessed.toLocaleString()}`);
  console.log(`  Total imported: ${totalImported.toLocaleString()}`);
  console.log(`  Total skipped: ${totalSkipped.toLocaleString()}`);

  return totalImported;
}

/**
 * Configure Meilisearch index settings
 */
async function configureIndex() {
  console.log('\nConfiguring Meilisearch index...');

  const index = client.index(INDEX_NAME);

  // Set searchable attributes
  await index.updateSearchableAttributes([
    'name',
    'brand',
    'id', // barcode
  ]);

  // Set filterable attributes (for barcode lookup)
  await index.updateFilterableAttributes([
    'id',
    'categories',
  ]);

  // Set sortable attributes
  await index.updateSortableAttributes([
    'calories_100g',
  ]);

  // Set displayed attributes
  await index.updateDisplayedAttributes([
    'id',
    'name',
    'brand',
    'calories_100g',
    'serving_size',
    'categories',
  ]);

  // Configure ranking rules for better food search
  await index.updateRankingRules([
    'words',
    'typo',
    'proximity',
    'attribute',
    'sort',
    'exactness',
  ]);

  console.log('  Index configured');
}

/**
 * Clean up downloaded files
 */
function cleanup() {
  console.log('\nCleaning up...');

  if (existsSync(LOCAL_FILE)) {
    unlinkSync(LOCAL_FILE);
    console.log(`  Removed ${LOCAL_FILE}`);
  }

  if (existsSync(EXTRACTED_FILE)) {
    unlinkSync(EXTRACTED_FILE);
    console.log(`  Removed ${EXTRACTED_FILE}`);
  }
}

/**
 * Main import function
 */
async function main() {
  console.log('===========================================');
  console.log('  OpenFoodFacts to Meilisearch Importer');
  console.log('===========================================\n');

  console.log(`Meilisearch host: ${MEILISEARCH_HOST}`);
  console.log(`Index name: ${INDEX_NAME}`);
  console.log(`Max products: ${MAX_PRODUCTS === Infinity ? 'unlimited' : MAX_PRODUCTS.toLocaleString()}`);

  try {
    // Test Meilisearch connection
    console.log('\nTesting Meilisearch connection...');
    const health = await client.health();
    console.log(`  Status: ${health.status}`);

    // Configure index
    await configureIndex();

    // Download data if not exists
    if (!existsSync(LOCAL_FILE)) {
      await downloadFile(DATA_URL, LOCAL_FILE);
    } else {
      console.log(`\nUsing existing file: ${LOCAL_FILE}`);
    }

    // Extract if needed
    if (!existsSync(EXTRACTED_FILE)) {
      await extractFile(LOCAL_FILE, EXTRACTED_FILE);
    } else {
      console.log(`Using existing file: ${EXTRACTED_FILE}`);
    }

    // Import to Meilisearch
    const imported = await importToMeilisearch(EXTRACTED_FILE);

    // Wait for indexing to complete
    console.log('\nWaiting for indexing to complete...');
    const tasks = await client.getTasks({ indexUids: [INDEX_NAME], statuses: ['enqueued', 'processing'] });
    if (tasks.results.length > 0) {
      console.log(`  ${tasks.results.length} tasks pending...`);
      await index.waitForTasks(tasks.results.map(t => t.uid));
    }
    console.log('  Indexing complete!');

    // Get final stats
    const stats = await client.index(INDEX_NAME).getStats();
    console.log(`\nFinal index stats:`);
    console.log(`  Documents: ${stats.numberOfDocuments.toLocaleString()}`);
    console.log(`  Index size: ${(stats.databaseSize / 1e6).toFixed(2)} MB`);

    // Cleanup (optional - comment out if you want to keep files for incremental updates)
    // cleanup();

    console.log('\n✅ Import successful!');

  } catch (error) {
    console.error('\n❌ Import failed:', error.message);
    process.exit(1);
  }
}

// Run import
main();
