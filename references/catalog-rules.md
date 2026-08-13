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

| Type | Shopify category | Price | Allowed sizes |
|---|---:|---:|---|
| T-Shirts | `aa-1-13-8` | 29.99 | S, M, L, XL, 2XL |
| Tank Tops | `aa-1-13-9` | 25.99 | S, M, L, XL, 2XL, 3XL |
| Sweatshirts | `aa-1-13-14` | 39.99 | M, L, XL, 2XL, 3XL |
| Hoodies | `aa-1-13-13` | 41.99 | M, L, XL, 2XL, 3XL |

When a batch introduces a type not represented in the current source/history, compare against active products in the live snapshot before applying a new rule.

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

- Titles: natural English, front-load the design phrase, append a concise garment descriptor, avoid keyword stuffing.
- Body HTML: describe the design, garment, fit/use case, and gifting angle without unsupported claims.
- SEO title: concise and distinct; target about 50–60 characters when practical.
- SEO description: useful sales summary; target about 140–160 characters when practical.
- Image alt: describe the visible graphic and garment type; do not stuff tags.
- Preserve the original meaning, scripture reference, spelling, and punctuation visible in the artwork.

## Tag rules

- Keep helpful customer-facing tags consistent with existing products in the same store.
- Add one readable semantic series label for review.
- Add exactly one series machine tag taken from the live collection condition.
- Do not add `new-in` to the import CSV. Shopify Flow owns this tag: it adds the tag for new products and removes it after 30 days.
- Do not add multiple competing `series-*` tags.
- Do not use a readable series label as a substitute for the machine tag.
