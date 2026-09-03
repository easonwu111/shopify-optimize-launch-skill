# Catalog rules

Use these transformation defaults together with [approved-store-mapping.json](approved-store-mapping.json). Refresh the mapping only when a trigger in `SKILL.md` occurs.

## Store routing

| Store | Shopify domain | Use for |
|---|---|---|
| Regular Mess | `regularmess-un1uhgsk.myshopify.com` | sarcasm, attitude, introvert/overthinking, adulting/aging, self-deprecating and general irreverent humor |
| Let Faith Lead | `letfaithlead-kxmefpyd.myshopify.com` | Jesus, cross, scripture, Bible verses, Armor of God, faith and Christian humor |

Do not classify by supplier SKU alone. Use visible design text, imagery, and concept. If a design is genuinely ambiguous, inspect the product image and flag the decision in the review output.

## Current semantic series

Regular Mess:

- Sarcasm & Attitude
- Introvert & Overthinking
- Adulting & Aging

Let Faith Lead:

- Jesus & the Cross
- Bible Verses & Scripture
- Armor of God
- Christian Humor

These names aid classification and human review. Their exact approved machine tags are stored in `approved-store-mapping.json`; never derive a machine tag from a readable label.

## Product defaults

| Type | Price | Allowed sizes |
|---|---:|---|
| T-Shirts | 30.00 | S, M, L, XL, 2XL |
| Tank Tops | 26.00 | S, M, L, XL, 2XL, 3XL |
| Sweatshirts | 40.00 | M, L, XL, 2XL, 3XL |
| Hoodies | 42.00 | M, L, XL, 2XL, 3XL |

When a batch introduces a product type without an approved default price, stop and ask the user for the regular price. Do not inspect live products to infer or benchmark the answer.

### Integer-price policy

- Both stores use whole-dollar regular prices for new imports. Write them as monetary values such as `30.00`; never reintroduce `.99` endings.
- When converting a previously approved `.99` price, increase it by `0.01` to the next whole dollar: `25.99 → 26.00`, `29.99 → 30.00`, `39.99 → 40.00`, and `41.99 → 42.00`.
- Do not preserve a legacy `.99` manual override by default. A batch-specific exception requires explicit user approval and must be recorded in the verification report.
- For a new product type, ask the user directly for the regular price. Do not use current live products, historical prices, averages, or neighboring product types as a substitute for the user's answer.

### Product Category

- Take the exact approved `fullName` path for each product type from `approved-store-mapping.json`.
- Write that full path into the CSV `Product Category` column, e.g. `服饰与配饰 > 服装 > 服装上衣 > T 恤`.
- Never hardcode taxonomy IDs (`aa-1-13-8`) or English paths (`Apparel & Accessories > Clothing > Tops > T-Shirts`): store taxonomies can be localized, and the CSV importer silently rejects mismatched values ("invalid product category").

All variants:

- regular price: positive whole-dollar monetary value; use `.00` in the CSV for clarity
- compare-at price: completely blank; never write `0`, `0.00`, an MSRP, or any other strikethrough price
- inventory tracker: `shopify`
- inventory quantity: `0`
- inventory policy: `continue`
- fulfillment service: `manual`
- requires shipping: `TRUE`
- taxable: `TRUE`
- weight unit: preserve the valid source convention

All products:

- status: `draft`
- published: `FALSE`
- vendor: exactly `Regular Mess` or `Let Faith Lead`
- `Type`: exact pluralized approved collection value, such as `T-Shirts` or `Tank Tops`

## Copy rules

- Titles: natural English, front-load the design phrase, append a concise garment descriptor, avoid keyword stuffing; keep the total length roughly 40-95 characters, in line with existing store titles.
- Body HTML: describe the design, garment, fit/use case, and gifting angle without unsupported claims. Match the store's existing short format (opening sentence, then a Design/fabric/neckline-and-sleeves/washing bullet list, then a gifting sentence). Strip supplier spec sections and size-table templates.
- SEO title: concise and distinct; target about 50–60 characters when practical.
- SEO description: useful sales summary; target about 140–160 characters when practical.
- Image alt: describe the visible graphic and garment type; do not stuff tags.
- Preserve the original meaning, scripture reference, spelling, and punctuation visible in the artwork.

## Image rules

- Keep only images that actually belong to the product; drop generic images shared across products (verify with OCR or visual inspection when wording is ambiguous).
- Treat `Image Src` and `Image Position` as product-wide gallery fields. The variant row containing an `Image Src` value does not bind that image to the row's color; only `Variant Image` creates the color/variant binding.
- For each product, collect every nonblank `Image Src` and sort by numeric `Image Position`. This is the source site's product-gallery order. Do not associate an `Image Src` with the Color on the same physical CSV row; those fields are independent.
- Build the Color-to-image mapping only from `Variant Image`. Derive the source-site Color/SKC order by locating each Color's distinct `Variant Image` in the ordered source gallery. Keep all variants for each color in one contiguous block and arrange those blocks in that derived order, because the storefront SKC thumbnails follow Shopify's Color option-value order.
- Shopify can append a UUID suffix to duplicate imported filenames; normalize only that deterministic suffix when matching source URLs to Shopify CDN URLs. For completely renamed files, require a documented content-level match before using a manual key mapping. Filename similarity or current row position alone is not evidence.
- For repair of an existing Shopify product after approved color filtering, renaming, or substitution, sort retained live Color values by the source-gallery position of each live Color's bound variant image. Live Color labels and SKU sets may differ from the unfiltered source, but every retained live color must resolve to one distinct, content-verified source-gallery image; otherwise skip that product's Color/SKC reorder.
- Source `Image Position` values may contain gaps or start above `1`; their numeric ascending order is still authoritative. Stop for manual review when source positions are invalid or duplicated; a Color has blank or multiple `Variant Image` values; a `Variant Image` is absent from the product gallery; or multiple Colors share one `Variant Image`. Do not fall back to physical CSV row order. Normalize final Shopify/import positions to continuous `1..N`.
- Bind every size of one color to the same nonblank `Variant Image`. Every `Variant Image` URL must also appear in the product's `Image Src` set.
- After filtering colors or images, remove media used only by a removed color unless the user explicitly approved keeping it as gallery content.
- After filtering, preserve the relative order of every retained image from the source site's ordered gallery, then renumber `Image Position` exactly `1..N` with no blanks, gaps, or duplicates.
- Keep the first retained source-gallery image at position `1`. Never move a Color's `Variant Image` to position `1` merely because that Color appears first in the CSV's variant rows.
- Run `scripts/validate-image-order.ps1` against every final store CSV. Do not deliver a file when the validator exits nonzero.

## Tag rules

- Keep helpful customer-facing tags consistent with existing products in the same store.
- Add one readable semantic series label for review.
- Add exactly one series machine tag taken from the approved store mapping.
- Do not add `new-in` to the import CSV. Shopify Flow owns this tag: it adds the tag for new products and removes it after 30 days.
- Do not add multiple competing `series-*` tags.
- Do not use a readable series label as a substitute for the machine tag.
