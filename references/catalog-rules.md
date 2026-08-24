# Catalog rules

Use these as transformation defaults, but let the live collection snapshot override every collection tag and `Type` condition.

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

These names aid classification and human review. Always obtain their current machine tags from the live collection `ruleSet`; never derive or remember the machine tag as the only evidence.

## Product defaults

| Type | Price | Allowed sizes |
|---|---:|---|
| T-Shirts | 29.99 | S, M, L, XL, 2XL |
| Tank Tops | 25.99 | S, M, L, XL, 2XL, 3XL |
| Sweatshirts | 39.99 | M, L, XL, 2XL, 3XL |
| Hoodies | 41.99 | M, L, XL, 2XL, 3XL |

When a batch introduces a type not represented in the current source/history, compare against active products in the live snapshot before applying a new rule.

### Product Category

- Take the exact `fullName` path for each product type from the live snapshot (`productCategory.productTaxonomyNode.fullName`, exposed as `categoryByType` in `live-context-summary.json`).
- Write that full path into the CSV `Product Category` column, e.g. `服饰与配饰 > 服装 > 服装上衣 > T 恤`.
- Never hardcode taxonomy IDs (`aa-1-13-8`) or English paths (`Apparel & Accessories > Clothing > Tops > T-Shirts`): store taxonomies can be localized, and the CSV importer silently rejects mismatched values ("invalid product category").

All variants:

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
- `Type`: exact pluralized live collection value, such as `T-Shirts` or `Tank Tops`

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
- Preserve the reviewed first-seen Color option order from the source and keep all variants for each color in one contiguous block. The storefront SKC thumbnail order follows Shopify's Color option-value order.
- Bind every size of one color to the same nonblank `Variant Image`. Every `Variant Image` URL must also appear in the product's `Image Src` set.
- After filtering colors or images, remove media used only by a removed color unless the user explicitly approved keeping it as gallery content.
- Renumber `Image Position` exactly `1..N` with no blanks, gaps, or duplicates after the final image set is known.
- Set position `1` to the first Color option's `Variant Image`. This keeps the product featured image aligned with the current themes, which open the product page on the first available variant image.
- Run `scripts/validate-image-order.ps1` against every final store CSV. Do not deliver a file when the validator exits nonzero.

## Tag rules

- Keep helpful customer-facing tags consistent with existing products in the same store.
- Add one readable semantic series label for review.
- Add exactly one series machine tag taken from the live collection condition.
- Do not add `new-in` to the import CSV. Shopify Flow owns this tag: it adds the tag for new products and removes it after 30 days.
- Do not add multiple competing `series-*` tags.
- Do not use a readable series label as a substitute for the machine tag.
