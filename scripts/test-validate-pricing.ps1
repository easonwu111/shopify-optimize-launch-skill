$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$validator = Join-Path $PSScriptRoot "validate-pricing.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shopify-pricing-validator-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function Write-Fixture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [string[]]$Lines
  )
  $path = Join-Path $tempRoot $Name
  $Lines | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-Case {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $true)]
    [int]$ExpectedExitCode,
    [string]$ExpectedIssueCode = ""
  )

  $reportPath = Join-Path $tempRoot "$Name-report.json"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -CsvPath $CsvPath -ReportPath $reportPath | Out-Null
  $actualExitCode = $LASTEXITCODE
  if ($actualExitCode -ne $ExpectedExitCode) {
    throw "$Name expected exit $ExpectedExitCode but received $actualExitCode."
  }
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  if ($ExpectedExitCode -eq 0 -and $report.status -ne "PASS") {
    throw "$Name expected PASS report."
  }
  if ($ExpectedIssueCode) {
    if ($ExpectedIssueCode -notin @($report.issues.code)) {
      throw "$Name expected issue '$ExpectedIssueCode'."
    }
  }
  return [pscustomobject]@{ name = $Name; status = "PASS"; validatorExitCode = $actualExitCode }
}

try {
  $header = 'Handle,Title,Type,Variant SKU,Variant Price,Variant Compare At Price'
  $good = Write-Fixture -Name "good.csv" -Lines @(
    $header,
    'shirt-one,Shirt One,T-Shirts,SKU-1,30.00,',
    'shirt-one,,,SKU-2,30,',
    'tank-one,Tank One,Tank Tops,SKU-3,26.00,'
  )
  $ending99 = Write-Fixture -Name "ending99.csv" -Lines @(
    $header,
    'shirt-one,Shirt One,T-Shirts,SKU-1,29.99,'
  )
  $compareAt = Write-Fixture -Name "compare-at.csv" -Lines @(
    $header,
    'shirt-one,Shirt One,T-Shirts,SKU-1,30.00,42.99'
  )
  $blankPrice = Write-Fixture -Name "blank-price.csv" -Lines @(
    $header,
    'shirt-one,Shirt One,T-Shirts,SKU-1,,'
  )

  $results = @(
    Invoke-Case -Name "whole-dollar-prices-pass" -CsvPath $good -ExpectedExitCode 0
    Invoke-Case -Name "ending-99-fails" -CsvPath $ending99 -ExpectedExitCode 1 -ExpectedIssueCode "variant_price_not_integer"
    Invoke-Case -Name "compare-at-fails" -CsvPath $compareAt -ExpectedExitCode 1 -ExpectedIssueCode "compare_at_not_blank"
    Invoke-Case -Name "blank-price-fails" -CsvPath $blankPrice -ExpectedExitCode 1 -ExpectedIssueCode "variant_price_blank"
  )
  [pscustomobject]@{
    status = "PASS"
    testCount = $results.Count
    results = $results
  } | ConvertTo-Json -Depth 6
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
