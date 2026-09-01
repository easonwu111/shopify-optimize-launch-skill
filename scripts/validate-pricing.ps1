param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,

  [Parameter(Mandatory = $true)]
  [string]$ReportPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-CellText {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Row,
    [string]$Column
  )

  if ([string]::IsNullOrWhiteSpace($Column)) {
    return ""
  }
  $property = $Row.PSObject.Properties[$Column]
  if ($null -eq $property -or $null -eq $property.Value) {
    return ""
  }
  return ([string]$property.Value).Trim()
}

function Resolve-Column {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Headers,
    [Parameter(Mandatory = $true)]
    [string[]]$Candidates,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  foreach ($candidate in $Candidates) {
    foreach ($header in $Headers) {
      if ([string]::Equals($header, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $header
      }
    }
  }
  throw "Missing required Shopify CSV column '$Label'. Accepted headers: $($Candidates -join ', ')."
}

function New-Issue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Code,
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [hashtable]$Details = @{}
  )

  return [pscustomobject]@{
    severity = "error"
    code = $Code
    message = $Message
    details = [pscustomobject]$Details
  }
}

$resolvedCsv = [System.IO.Path]::GetFullPath($CsvPath)
if (-not (Test-Path -LiteralPath $resolvedCsv -PathType Leaf)) {
  throw "CSV file not found: $resolvedCsv"
}
$rows = @(Import-Csv -LiteralPath $resolvedCsv -Encoding UTF8)
if ($rows.Count -eq 0) {
  throw "CSV contains no data rows: $resolvedCsv"
}

$headers = @($rows[0].PSObject.Properties.Name)
$handleColumn = Resolve-Column -Headers $headers -Candidates @("Handle", "URL handle") -Label "Handle"
$skuColumn = Resolve-Column -Headers $headers -Candidates @("Variant SKU", "SKU") -Label "Variant SKU"
$priceColumn = Resolve-Column -Headers $headers -Candidates @("Variant Price", "Price") -Label "Variant Price"
$compareAtColumn = Resolve-Column -Headers $headers -Candidates @("Variant Compare At Price", "Variant Compare-at Price", "Compare-at price", "Compare At Price") -Label "Variant Compare At Price"

$issues = New-Object 'System.Collections.Generic.List[object]'
$priceCounts = @{}
$variantCount = 0
$rowNumber = 1
foreach ($row in $rows) {
  $rowNumber += 1
  $handle = Get-CellText -Row $row -Column $handleColumn
  $sku = Get-CellText -Row $row -Column $skuColumn
  $priceText = Get-CellText -Row $row -Column $priceColumn
  $compareAtText = Get-CellText -Row $row -Column $compareAtColumn

  if ($compareAtText) {
    $issues.Add((New-Issue -Code "compare_at_not_blank" -Message "Compare-at price must be completely blank for handle '$handle', SKU '$sku'." -Details @{ row = $rowNumber; handle = $handle; sku = $sku; value = $compareAtText }))
  }

  if (-not $sku) {
    continue
  }
  $variantCount += 1

  if (-not $priceText) {
    $issues.Add((New-Issue -Code "variant_price_blank" -Message "Variant price is blank for handle '$handle', SKU '$sku'." -Details @{ row = $rowNumber; handle = $handle; sku = $sku }))
    continue
  }

  [decimal]$price = 0
  $parsed = [decimal]::TryParse(
    $priceText,
    [System.Globalization.NumberStyles]::Number,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [ref]$price
  )
  if (-not $parsed) {
    $issues.Add((New-Issue -Code "variant_price_not_numeric" -Message "Variant price '$priceText' is not a valid invariant monetary value for handle '$handle', SKU '$sku'." -Details @{ row = $rowNumber; handle = $handle; sku = $sku; value = $priceText }))
    continue
  }
  if ($price -le 0) {
    $issues.Add((New-Issue -Code "variant_price_not_positive" -Message "Variant price must be positive for handle '$handle', SKU '$sku'." -Details @{ row = $rowNumber; handle = $handle; sku = $sku; value = $priceText }))
    continue
  }
  if ([decimal]::Truncate($price) -ne $price) {
    $issues.Add((New-Issue -Code "variant_price_not_integer" -Message "Variant price '$priceText' is not a whole-dollar price for handle '$handle', SKU '$sku'." -Details @{ row = $rowNumber; handle = $handle; sku = $sku; value = $priceText }))
    continue
  }

  $normalized = $price.ToString("0.00", [System.Globalization.CultureInfo]::InvariantCulture)
  if (-not $priceCounts.ContainsKey($normalized)) {
    $priceCounts[$normalized] = 0
  }
  $priceCounts[$normalized] += 1
}

if ($variantCount -eq 0) {
  $issues.Add((New-Issue -Code "no_variant_rows" -Message "No rows with a nonblank variant SKU were found."))
}

$productCount = @($rows | ForEach-Object { Get-CellText -Row $_ -Column $handleColumn } | Where-Object { $_ } | Sort-Object -Unique).Count
$pricePoints = @($priceCounts.Keys | Sort-Object { [decimal]$_ } | ForEach-Object {
  [pscustomobject]@{
    price = $_
    variantCount = $priceCounts[$_]
  }
})
$status = if ($issues.Count -eq 0) { "PASS" } else { "FAIL" }
$report = [pscustomobject]@{
  generatedAt = [DateTime]::UtcNow.ToString("o")
  status = $status
  csvPath = $resolvedCsv
  rule = "Every variant price must be a positive whole-dollar value; every compare-at price must be blank."
  summary = [pscustomobject]@{
    productCount = $productCount
    variantCount = $variantCount
    pricePointCount = $pricePoints.Count
    issueCount = $issues.Count
  }
  pricePoints = $pricePoints
  issues = $issues.ToArray()
}

$resolvedReport = [System.IO.Path]::GetFullPath($ReportPath)
$reportDirectory = Split-Path -Parent $resolvedReport
if ($reportDirectory) {
  New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReport -Encoding UTF8
$report | ConvertTo-Json -Depth 8

if ($status -ne "PASS") {
  exit 1
}
