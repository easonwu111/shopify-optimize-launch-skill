param(
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$shopifyCommand = Get-Command shopify.cmd -ErrorAction Stop
$shopify = $shopifyCommand.Source
$skillRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$queryFile = Join-Path $skillRoot "references\live-context.graphql"

if (-not (Test-Path -LiteralPath $queryFile)) {
  throw "Missing GraphQL query: $queryFile"
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

$stores = @(
  [pscustomobject]@{
    key = "regular-mess"
    domain = "regularmess-un1uhgsk.myshopify.com"
  },
  [pscustomobject]@{
    key = "let-faith-lead"
    domain = "letfaithlead-kxmefpyd.myshopify.com"
  }
)

function Invoke-ShopifyCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $commandOutput = & $shopify @Arguments 2>&1
    $commandExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  return [pscustomobject]@{
    ExitCode = $commandExitCode
    Output = ($commandOutput | Out-String)
  }
}

$authResult = Invoke-ShopifyCommand -Arguments @("store", "auth", "list")
if ($authResult.ExitCode -ne 0) {
  throw "Shopify authentication check failed. Run 'shopify store auth' for both stores."
}
$authOutput = $authResult.Output

$summaries = @()
foreach ($store in $stores) {
  if ($authOutput -notmatch [regex]::Escape(($store.domain -replace '\.myshopify\.com$', ''))) {
    throw "Store is not authenticated: $($store.domain). Run 'shopify store auth' first."
  }

  $outputFile = Join-Path $resolvedOutput "$($store.key).json"
  $queryResult = Invoke-ShopifyCommand -Arguments @(
    "store", "execute",
    "--store", $store.domain,
    "--query-file", $queryFile,
    "--json",
    "--output-file", $outputFile
  )
  if ($queryResult.ExitCode -ne 0) {
    Write-Error $queryResult.Output
    throw "Live Shopify query failed for $($store.domain). No final import CSV should be generated."
  }

  $payload = Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $payload.shop -or -not $payload.collections -or -not $payload.products) {
    throw "Incomplete Shopify response for $($store.domain)."
  }
  if ($payload.shop.myshopifyDomain -ne $store.domain) {
    throw "Store-domain mismatch. Expected $($store.domain), received $($payload.shop.myshopifyDomain)."
  }

  $collectionRules = @(
    foreach ($collection in $payload.collections.nodes) {
      if ($null -ne $collection.ruleSet) {
        [pscustomobject]@{
          title = $collection.title
          handle = $collection.handle
          appliedDisjunctively = $collection.ruleSet.appliedDisjunctively
          rules = @($collection.ruleSet.rules)
        }
      }
    }
  )

  $productTags = @(
    if ($payload.productTags -and $payload.productTags.nodes) {
      $payload.productTags.nodes
    } else {
      $payload.products.nodes.tags
    }
  ) | Where-Object { $_ } | Sort-Object -Unique

  $categoryByType = @{}
  foreach ($node in $payload.products.nodes) {
    if ($node.productCategory -and $node.productCategory.productTaxonomyNode -and $node.productType -and -not $categoryByType.ContainsKey($node.productType)) {
      $categoryByType[$node.productType] = $node.productCategory.productTaxonomyNode.fullName
    }
  }

  $summaries += [pscustomobject]@{
    key = $store.key
    shop = $payload.shop
    fetchedAt = (Get-Date).ToUniversalTime().ToString("o")
    rawFile = $outputFile
    automaticCollections = $collectionRules
    productCountSampled = @($payload.products.nodes).Count
    productTags = $productTags
    seriesTags = @($productTags | Where-Object { $_ -like "series-*" })
    vendors = @($payload.products.nodes.vendor | Where-Object { $_ } | Sort-Object -Unique)
    productTypes = @($payload.products.nodes.productType | Where-Object { $_ } | Sort-Object -Unique)
    categoryByType = $categoryByType
  }
}

$summaryFile = Join-Path $resolvedOutput "live-context-summary.json"
$summaries | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryFile -Encoding utf8
Write-Output $summaryFile
