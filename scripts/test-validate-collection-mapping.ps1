$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "validate-collection-mapping.ps1"
$powershellPath = (Get-Process -Id $PID).Path
$mappingPath = Join-Path (Split-Path -Parent $PSScriptRoot) "references\approved-store-mapping.json"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shopify-collection-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
  $validCsv = Join-Path $tempRoot "valid.csv"
  $invalidCsv = Join-Path $tempRoot "invalid.csv"
  $validReport = Join-Path $tempRoot "valid-report.json"
  $invalidReport = Join-Path $tempRoot "invalid-report.json"
  $invalidError = Join-Path $tempRoot "invalid-stderr.txt"

  $mapping = Get-Content -LiteralPath $mappingPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $category = $mapping.stores.'regularmess-un1uhgsk.myshopify.com'.productTypes.'T-Shirts'

  @([pscustomobject]@{
    Handle = "good-product"
    Title = "Good Product"
    Vendor = "Regular Mess"
    Type = "T-Shirts"
    Tags = "Sarcasm & Attitude, series-sarcasm-attitude"
    'Product Category' = $category
  }) | Export-Csv -LiteralPath $validCsv -NoTypeInformation -Encoding UTF8

  @([pscustomobject]@{
    Handle = "bad-product"
    Title = "Bad Product"
    Vendor = "Regular Mess"
    Type = "T-Shirts"
    Tags = "Sarcasm & Attitude, series-introvert-overthinking"
    'Product Category' = "Wrong Category"
  }) | Export-Csv -LiteralPath $invalidCsv -NoTypeInformation -Encoding UTF8

  & $powershellPath -NoProfile -File $scriptPath -CsvPath $validCsv -StoreDomain "regularmess-un1uhgsk.myshopify.com" -ReportPath $validReport
  if ($LASTEXITCODE -ne 0) {
    throw "Valid fixture should pass"
  }

  $invalidProcess = Start-Process -FilePath $powershellPath -ArgumentList @(
    "-NoProfile",
    "-File", $scriptPath,
    "-CsvPath", $invalidCsv,
    "-StoreDomain", "regularmess-un1uhgsk.myshopify.com",
    "-ReportPath", $invalidReport
  ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardError $invalidError
  if ($invalidProcess.ExitCode -eq 0) {
    throw "Invalid fixture should fail"
  }

  $invalidPayload = Get-Content -LiteralPath $invalidReport -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($invalidPayload.failureCount -ne 2) {
    throw "Expected two invalid-fixture failures, got $($invalidPayload.failureCount)"
  }

  Write-Output "PASS: collection mapping validator accepts valid input and rejects mismatched series/category input."
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
