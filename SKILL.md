---
name: shopify-optimize-launch
description: End-to-end workflow for Shopify new-product launches. Use when the user says “优化上新”, “产品上新”, “整理/生成 Shopify 导入文件”, asks to split a product CSV between Regular Mess and Let Faith Lead, or needs collection-ready tags. Use the approved store mapping to optimize content, split by store, attach exact collection tags, and preserve the source site's gallery and color/SKC image order. Refresh Shopify configuration only when a defined change trigger occurs.
---

# Shopify Optimize Launch

## Outcome

Turn one supplier/product CSV into two import-ready Shopify CSV files, one for Regular Mess and one for Let Faith Lead. The user should only need to provide the source file and say “优化上新”.

The versioned approved store mapping is the normal source of truth for launch work. It contains collection rules that were verified read-only against Shopify. Do not query both stores again on every routine batch.

## Mandatory workflow

### 1. Inspect the source

- Use the Spreadsheets skill and its bundled runtime for CSV reading, authoring, rendering, and verification.
- Preserve handles, variant SKUs, option relationships, source image URLs, and variant-image bindings.
- Group rows by `Handle`; treat the row containing `Title` as the product-level row.
- For each Handle, collect all nonblank `Image Src` values and sort them by numeric `Image Position`; this ordered gallery is the source site's image order. The physical CSV row containing an `Image Src` does not associate that image with the row's Color.
- Build each Color's image binding only from `Variant Image`. Derive the source-site Color/SKC order from where those distinct `Variant Image` URLs first occur in the ordered gallery; never derive it from the first-seen order of `Option1 Value` rows.
- When Shopify has appended a UUID to an imported filename, normalize only that deterministic suffix before matching. If a filename was replaced entirely, use a manual mapping only after content-level verification (for example, visual comparison or a reliable image fingerprint); never guess from row position or a vaguely similar name.
- When repairing an already-imported product after approved color filtering, renaming, or substitution, derive the retained Shopify Color order from each live Color's single bound variant image and that image's position in the source gallery. Do not require the live Color label or SKU set to equal the source when the launch transformation intentionally changed them; require every retained live color to have one distinct, content-verified gallery binding before reordering.
- Source `Image Position` values may contain gaps or start above `1`; preserve their numeric ascending order. Stop and flag the product only when a position is invalid or duplicated, or when a Color has no unique `Variant Image` present in the gallery. Final Shopify/import positions must still be normalized to continuous `1..N`.
- Inspect representative product images when wording or store/series classification is ambiguous.

### 2. Load the approved store mapping

Read [approved-store-mapping.json](references/approved-store-mapping.json) before writing a final import CSV. Use its exact store domain, Vendor, readable series label, `series-*` tag, `Type`, and `Product Category` values.

Do not run a live Shopify preflight merely because a new batch started or time has passed. Refresh the mapping only when at least one of these triggers is present:

- the user says a collection, tag, product type, or product category changed;
- the batch needs a series or product type absent from the approved mapping;
- a previous import failed the post-import collection-membership audit;
- the local mapping file is missing, malformed, or internally inconsistent;
- the user explicitly asks for a live refresh.

When a refresh trigger is present, run this read-only command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\fetch-live-context.ps1" -OutputDirectory "<task-temp-dir>\live-shopify"
```

Read both `live-context-summary.json` and the two raw JSON files, compare them with the approved mapping, and extract only the changed values needed for the task:

- every automatic collection's `ruleSet`;
- exact tag conditions such as `series-*` and `new-in`;
- exact product-type conditions;
- each product type's exact `Product Category` fullName path (`categoryByType`);
- existing product tag vocabulary, vendors, types, and naming patterns.

Refresh rules:

- The command must remain read-only. Never add `--allow-mutations`.
- If the refresh was triggered by a possible configuration change and Shopify CLI is missing, either store is not authenticated, a query fails, or the returned store domain does not match, stop before producing the final CSV and ask the user to authenticate that store.
- A routine batch with only known mapped values does not require Shopify CLI authentication and must not be blocked by the absence of a new live snapshot.
- Save any refreshed live snapshot with the task's temporary verification artifacts and update the approved mapping only from confirmed collection rules.

### 3. Optimize and classify

Read [catalog-rules.md](references/catalog-rules.md) before transforming the file.

For each product:

- assign exactly one destination store from its message/design;
- optimize the English title, HTML description, SEO title, SEO description, image alt text, and useful descriptive tags;
- set `Product Category` to the approved fullName path for the product type (never use taxonomy IDs or an unapproved English path), plus correct `Type`, sizes, regular prices, inventory, fulfillment, shipping, tax, draft, and unpublished fields;
- use whole-dollar regular prices for both stores. Apply the default mapping in [catalog-rules.md](references/catalog-rules.md): T-Shirts `30.00`, Tank Tops `26.00`, Sweatshirts `40.00`, and Hoodies `42.00`. Never generate a `.99` ending unless the user explicitly approves a batch-specific exception;
- clear `Variant Compare At Price` for every variant; never create a strikethrough/sale price;
- assign exactly one semantic series;
- map that series to the exact approved collection rule instead of constructing a slug by memory.
- apply the image rules in [catalog-rules.md](references/catalog-rules.md) after every color or image filter; renumber media only after the final image set is known.

On the product-level row, include:

1. the readable series label for human review;
2. exactly one corresponding approved `series-*` machine tag;
3. the exact `Type` value required by the approved product-type collection.

`new-in` is managed by the user's Shopify Flow: the Flow adds it for new products and removes it after 30 days. Record this dependency in verification, but do not write `new-in` into the import CSV.

If a desired series has no matching approved automatic collection, flag it in the review output and do not invent a collection tag. Trigger a read-only mapping refresh.

If a product type has no approved price, stop and ask the user for that type's regular price. Do not benchmark, copy, average, or infer the price from live products.

### 4. Split the stores

Generate exactly two final CSVs:

- `Regular Mess-<date>上新-Shopify正式导入-集合标签已匹配.csv`
- `Let Faith Lead-<date>上新-Shopify正式导入-集合标签已匹配.csv`

Do not leave the user with a combined file as the primary deliverable. Do not mix vendors or SKUs between the two outputs.

### 5. Verify before delivery

Run the deterministic pricing gate once for each final store CSV:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\validate-pricing.ps1" `
  -CsvPath "<final-store-csv>" `
  -ReportPath "<task-temp-dir>\<store>-pricing-report.json"
```

The pricing gate must exit `0`. It blocks blank/non-numeric/non-positive variant prices, every non-integer regular price (including `.99`), and every nonblank compare-at value (`0` and `0.00` also fail).

Then run the deterministic image/SKC gate once for each final store CSV:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\validate-image-order.ps1" `
  -CsvPath "<final-store-csv>" `
  -SourceCsvPath "<source-csv>" `
  -ReportPath "<task-temp-dir>\<store>-image-order-report.json"
```

Both pricing and image-order commands must exit `0`. A nonzero exit blocks delivery; fix the CSV and rerun it. Keep all pricing and image-order JSON reports with the task verification artifacts and include their pass/fail totals in the final verification report.

Run the deterministic collection-mapping gate once for each final store CSV:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\validate-collection-mapping.ps1" `
  -CsvPath "<final-store-csv>" `
  -StoreDomain "<store>.myshopify.com" `
  -ReportPath "<task-temp-dir>\<store>-collection-mapping-report.json"
```

The collection-mapping gate must exit `0`. It verifies the exact Vendor, one approved readable series label, one matching machine tag, the approved `Type`, and the approved `Product Category` for every product. Passing means the CSV satisfies the recorded automatic-collection conditions; actual membership is confirmed only by the read-only post-import audit.

Re-import each generated CSV with the artifact tool and verify all of the following:

- headers match Shopify's expected import schema and order;
- product and variant counts reconcile to the source;
- every variant SKU is nonblank and globally unique across both store files;
- every product has exactly one image at position `1`, and positions are unique and continuous `1..N`;
- source back-view images representing retained colors remain in `Image Src`, including plain backs and images shared across products; reconcile these explicitly under the catalog image rules, since the image-order gate alone does not detect omitted back views;
- after any approved image filtering, the remaining `Image Src` values preserve their relative order from the source site's `Image Position` sequence and are renumbered continuously `1..N`;
- position `1` equals the first retained image from the source-site gallery; do not replace it merely to match the first physical Color row in the CSV;
- every color's variants are contiguous, follow the Color/SKC order derived from their `Variant Image` positions in the source gallery, and use exactly one nonblank `Variant Image` across all sizes;
- each retained Color keeps the same `Variant Image` URL as the source CSV;
- every `Variant Image` URL appears in that product's `Image Src` set;
- every `Variant Price` is a positive whole-dollar value and matches the catalog rule for its type; `.99` endings are failures unless the user explicitly approved and documented a batch-specific exception;
- every `Variant Compare At Price` value is completely blank; `0` and `0.00` are failures, not blank values;
- `Variant Inventory Tracker=shopify`, quantity `0`, policy `continue`, fulfillment `manual`, shipping/taxable true;
- each product is `draft` and `Published=FALSE`;
- each product has exactly one approved readable series label and its corresponding exact machine tag;
- `new-in` is absent from the import CSV because Shopify Flow owns that tag lifecycle;
- each product's `Type` satisfies the approved type-collection rule;
- each product's `Product Category` exactly matches the approved fullName for its type;
- titles, descriptions, SEO fields, and image alt text are nonblank and within Shopify-safe lengths;
- no formula/error strings or replacement characters are present.

Render a representative preview of both CSVs and visually inspect it. Produce a compact verification report that records the approved mapping version, any refresh snapshot time, and all pass/fail checks. Fix failures before delivery.

## Safety boundary

This skill authorizes read-only Shopify checks and local CSV creation. It does not authorize importing, publishing, changing collections, tagging live products, or any other Shopify mutation unless the user explicitly requests that action.

After the user imports, run a read-only follow-up audit before claiming that the products entered the intended collections. CSV validation proves rule compatibility, not final Shopify collection membership.
