param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,

  [Parameter(Mandatory = $true)]
  [string]$StoreDomain,

  [Parameter(Mandatory = $true)]
  [string]$ReportPath
)

$ErrorActionPreference = "Stop"

$skillRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$mappingPath = Join-Path $skillRoot "references\approved-store-mapping.json"

if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "CSV not found: $CsvPath"
}
if (-not (Test-Path -LiteralPath $mappingPath)) {
  throw "Approved store mapping not found: $mappingPath"
}

$mapping = Get-Content -LiteralPath $mappingPath -Raw -Encoding UTF8 | ConvertFrom-Json
$storeProperty = $mapping.stores.PSObject.Properties | Where-Object { $_.Name -eq $StoreDomain } | Select-Object -First 1
if ($null -eq $storeProperty) {
  throw "Store domain is not approved: $StoreDomain"
}
$store = $storeProperty.Value

$rows = @(Import-Csv -LiteralPath $CsvPath -Encoding UTF8)
$requiredHeaders = @("Handle", "Title", "Vendor", "Type", "Tags", "Product Category")
$headers = @($rows | Select-Object -First 1 | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
$missingHeaders = @($requiredHeaders | Where-Object { $_ -notin $headers })
if ($missingHeaders.Count -gt 0) {
  throw "Missing required headers: $($missingHeaders -join ', ')"
}

$approvedSeries = @{}
foreach ($property in $store.series.PSObject.Properties) {
  $approvedSeries[$property.Name] = [string]$property.Value
}
$approvedMachineTags = @($approvedSeries.Values)

$approvedTypes = @{}
foreach ($property in $store.productTypes.PSObject.Properties) {
  $approvedTypes[$property.Name] = [string]$property.Value
}

$failures = @()
$products = @()
$groups = @($rows | Group-Object -Property Handle)
foreach ($group in $groups) {
  if ([string]::IsNullOrWhiteSpace($group.Name)) {
    $failures += [pscustomobject]@{ handle = ""; check = "handle"; detail = "Blank Handle" }
    continue
  }

  $productRow = @($group.Group | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Title) } | Select-Object -First 1)
  if ($productRow.Count -eq 0) {
    $productRow = @($group.Group | Select-Object -First 1)
  }
  $row = $productRow[0]
  $tags = @([string]$row.Tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $readableMatches = @($approvedSeries.Keys | Where-Object { $_ -in $tags })
  $machineMatches = @($approvedMachineTags | Where-Object { $_ -in $tags })

  if ([string]$row.Vendor -ne [string]$store.vendor) {
    $failures += [pscustomobject]@{ handle = $group.Name; check = "vendor"; detail = "Expected '$($store.vendor)', got '$($row.Vendor)'" }
  }
  if ($readableMatches.Count -ne 1) {
    $failures += [pscustomobject]@{ handle = $group.Name; check = "readable-series"; detail = "Expected exactly one approved readable series label; found $($readableMatches.Count)" }
  }
  if ($machineMatches.Count -ne 1) {
    $failures += [pscustomobject]@{ handle = $group.Name; check = "series-tag"; detail = "Expected exactly one approved series machine tag; found $($machineMatches.Count)" }
  }
  if ($readableMatches.Count -eq 1 -and $machineMatches.Count -eq 1) {
    $expectedMachineTag = $approvedSeries[$readableMatches[0]]
    if ($machineMatches[0] -ne $expectedMachineTag) {
      $failures += [pscustomobject]@{ handle = $group.Name; check = "series-pair"; detail = "Readable series '$($readableMatches[0])' requires '$expectedMachineTag', got '$($machineMatches[0])'" }
    }
  }
  if (-not $approvedTypes.ContainsKey([string]$row.Type)) {
    $failures += [pscustomobject]@{ handle = $group.Name; check = "type"; detail = "Unapproved Type '$($row.Type)'" }
  } else {
    $expectedCategory = $approvedTypes[[string]$row.Type]
    if ([string]$row.'Product Category' -ne $expectedCategory) {
      $failures += [pscustomobject]@{ handle = $group.Name; check = "product-category"; detail = "Type '$($row.Type)' requires '$expectedCategory', got '$($row.'Product Category')'" }
    }
  }

  $products += [pscustomobject]@{
    handle = $group.Name
    type = [string]$row.Type
    readableSeries = @($readableMatches)
    machineSeriesTags = @($machineMatches)
  }
}

$report = [pscustomobject]@{
  passed = ($failures.Count -eq 0)
  csvPath = [System.IO.Path]::GetFullPath($CsvPath)
  storeDomain = $StoreDomain
  mappingSchemaVersion = $mapping.schemaVersion
  mappingVerifiedAt = $mapping.verifiedAt
  productCount = $products.Count
  failureCount = $failures.Count
  failures = @($failures)
  products = @($products)
}

$resolvedReport = [System.IO.Path]::GetFullPath($ReportPath)
$reportDirectory = Split-Path -Parent $resolvedReport
if ($reportDirectory) {
  New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedReport -Encoding UTF8

if ($failures.Count -gt 0) {
  Write-Error "Collection mapping validation failed with $($failures.Count) issue(s). Report: $resolvedReport"
  exit 1
}

Write-Output "Collection mapping validation passed for $($products.Count) product(s). Report: $resolvedReport"
