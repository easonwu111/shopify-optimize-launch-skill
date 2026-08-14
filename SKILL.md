---
name: shopify-optimize-launch
description: End-to-end workflow for Shopify new-product launches. Use when the user says “优化上新”, “产品上新”, “整理/生成 Shopify 导入文件”, asks to split a product CSV between Regular Mess and Let Faith Lead, or needs collection-ready tags. Before generating final CSVs, read both stores' live automatic-collection rules and existing product tags, then optimize content, split by store, attach exact live rule tags, and verify the files.
---

# Shopify Optimize Launch

## Outcome

Turn one supplier/product CSV into two import-ready Shopify CSV files, one for Regular Mess and one for Let Faith Lead. The user should only need to provide the source file and say “优化上新”.

The live Shopify configuration is the source of truth. Never rely only on remembered collection tags.

## Mandatory workflow

### 1. Inspect the source

- Use the Spreadsheets skill and its bundled runtime for CSV reading, authoring, rendering, and verification.
- Preserve handles, variant SKUs, option relationships, source image URLs, and variant-image bindings.
- Group rows by `Handle`; treat the row containing `Title` as the product-level row.
- Inspect representative product images when wording or store/series classification is ambiguous.

### 2. Run the live Shopify preflight

Before writing any final import CSV, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\fetch-live-context.ps1" -OutputDirectory "<task-temp-dir>\live-shopify"
```

Read both `live-context-summary.json` and the two raw JSON files. Extract:

- every automatic collection's `ruleSet`;
- exact tag conditions such as `series-*` and `new-in`;
- exact product-type conditions;
- each product type's exact `Product Category` fullName path (`categoryByType`);
- existing product tag vocabulary, vendors, types, and naming patterns.

Rules:

- The command must remain read-only. Never add `--allow-mutations`.
- If Shopify CLI is missing, either store is not authenticated, a query fails, or the returned store domain does not match, stop before producing the final CSV and ask the user to authenticate that store.
- Do not silently use cached or hardcoded collection rules as a substitute for a failed live query.
- Save the live snapshot with the task's temporary verification artifacts so the output is auditable.

### 3. Optimize and classify

Read [catalog-rules.md](references/catalog-rules.md) before transforming the file.

For each product:

- assign exactly one destination store from its message/design;
- optimize the English title, HTML description, SEO title, SEO description, image alt text, and useful descriptive tags;
- set `Product Category` to the live fullName path for the product type (never hardcode taxonomy IDs or English paths; store taxonomies can be localized), plus correct `Type`, sizes, regular prices, inventory, fulfillment, shipping, tax, draft, and unpublished fields;
- clear `Variant Compare At Price` for every variant; never create a strikethrough/sale price;
- assign exactly one semantic series;
- map that series to the exact live collection rule instead of constructing a slug by memory.

On the product-level row, include:

1. the readable series label for human review;
2. exactly one corresponding live `series-*` machine tag;
3. the exact `Type` value required by the live product-type collection.

`new-in` is managed by the user's Shopify Flow: the Flow adds it for new products and removes it after 30 days. Record this dependency in verification, but do not write `new-in` into the import CSV.

If a desired series has no matching live automatic collection, flag it in the review output and do not invent a collection tag.

### 4. Split the stores

Generate exactly two final CSVs:

- `Regular Mess-<date>上新-Shopify正式导入-集合标签已匹配.csv`
- `Let Faith Lead-<date>上新-Shopify正式导入-集合标签已匹配.csv`

Do not leave the user with a combined file as the primary deliverable. Do not mix vendors or SKUs between the two outputs.

### 5. Verify before delivery

Re-import each generated CSV with the artifact tool and verify all of the following:

- headers match Shopify's expected import schema and order;
- product and variant counts reconcile to the source;
- every variant SKU is nonblank and globally unique across both store files;
- every variant has its intended image binding;
- regular prices, sizes, category, and type follow the catalog rules;
- every `Variant Compare At Price` value is completely blank; `0` and `0.00` are failures, not blank values;
- `Variant Inventory Tracker=shopify`, quantity `0`, policy `continue`, fulfillment `manual`, shipping/taxable true;
- each product is `draft` and `Published=FALSE`;
- each product has exactly one readable series label and one exact live series tag;
- `new-in` is absent from the import CSV because Shopify Flow owns that tag lifecycle;
- each product's `Type` satisfies the live type-collection rule;
- each product's `Product Category` exactly matches the live fullName for its type;
- titles, descriptions, SEO fields, and image alt text are nonblank and within Shopify-safe lengths;
- no formula/error strings or replacement characters are present.

Render a representative preview of both CSVs and visually inspect it. Produce a compact verification report that records the live rule snapshot time and all pass/fail checks. Fix failures before delivery.

## Safety boundary

This skill authorizes read-only Shopify checks and local CSV creation. It does not authorize importing, publishing, changing collections, tagging live products, or any other Shopify mutation unless the user explicitly requests that action.

After the user imports, a read-only follow-up audit may verify that the products entered the intended collections.
