param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$validator = Join-Path $PSScriptRoot "validate-image-order.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("shopify-image-order-tests-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

function Write-Utf8Csv {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string[]]$Lines
  )

  [System.IO.File]::WriteAllLines($Path, $Lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-ValidationCase {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $true)]
    [string]$SourceCsvPath,
    [Parameter(Mandatory = $true)]
    [int]$ExpectedExitCode,
    [string]$ExpectedIssueCode
  )

  $reportPath = Join-Path $testRoot "$Name-report.json"
  $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator `
    -CsvPath $CsvPath `
    -SourceCsvPath $SourceCsvPath `
    -ReportPath $reportPath 2>&1
  $actualExitCode = $LASTEXITCODE

  if ($actualExitCode -ne $ExpectedExitCode) {
    throw "Case '$Name' returned exit code $actualExitCode; expected $ExpectedExitCode. Output: $($output -join ' ')"
  }
  if (-not (Test-Path -LiteralPath $reportPath)) {
    throw "Case '$Name' did not create a report."
  }

  $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($ExpectedExitCode -eq 0 -and -not $report.passed) {
    throw "Case '$Name' should pass but report.passed is false."
  }
  if ($ExpectedExitCode -ne 0 -and $report.passed) {
    throw "Case '$Name' should fail but report.passed is true."
  }
  if ($ExpectedIssueCode) {
    $codes = @($report.products | ForEach-Object { $_.issues } | ForEach-Object { $_.code })
    if ($codes -notcontains $ExpectedIssueCode) {
      throw "Case '$Name' did not report expected issue '$ExpectedIssueCode'. Actual: $($codes -join ', ')"
    }
  }

  [pscustomobject]@{
    name = $Name
    exitCode = $actualExitCode
    passed = $report.passed
    issueCount = $report.summary.issueCount
  }
}

try {
  $header = "Handle,Title,Option1 Name,Option1 Value,Option2 Name,Option2 Value,Variant SKU,Image Src,Image Position,Variant Image"
  $sourcePath = Join-Path $testRoot "source.csv"
  Write-Utf8Csv -Path $sourcePath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg",
    "sample-product,,,Blue,,M,SAMPLE-BLUE-M,https://example.com/detail.jpg,3,https://example.com/blue.jpg"
  )

  $validPath = Join-Path $testRoot "valid.csv"
  Copy-Item -LiteralPath $sourcePath -Destination $validPath

  $missingPositionOnePath = Join-Path $testRoot "missing-position-one.csv"
  Write-Utf8Csv -Path $missingPositionOnePath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,2,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,3,https://example.com/blue.jpg"
  )

  $featuredMismatchPath = Join-Path $testRoot "featured-mismatch.csv"
  Write-Utf8Csv -Path $featuredMismatchPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,2,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,1,https://example.com/blue.jpg",
    "sample-product,,,Blue,,M,SAMPLE-BLUE-M,https://example.com/detail.jpg,3,https://example.com/blue.jpg"
  )

  $colorOrderMismatchPath = Join-Path $testRoot "color-order-mismatch.csv"
  Write-Utf8Csv -Path $colorOrderMismatchPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Blue,Size,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,1,https://example.com/blue.jpg",
    "sample-product,,,Blue,,M,SAMPLE-BLUE-M,,,https://example.com/blue.jpg",
    "sample-product,,,Black,,S,SAMPLE-BLACK-S,https://example.com/black.jpg,2,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,https://example.com/detail.jpg,3,https://example.com/black.jpg"
  )

  $inconsistentBindingPath = Join-Path $testRoot "inconsistent-binding.csv"
  Write-Utf8Csv -Path $inconsistentBindingPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black-2.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg",
    "sample-product,,,Blue,,M,SAMPLE-BLUE-M,https://example.com/detail.jpg,3,https://example.com/blue.jpg"
  )

  $blankImagePositionPath = Join-Path $testRoot "blank-image-position.csv"
  Write-Utf8Csv -Path $blankImagePositionPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )

  $blankVariantImagePath = Join-Path $testRoot "blank-variant-image.csv"
  Write-Utf8Csv -Path $blankVariantImagePath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,,",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )

  $missingGalleryBindingPath = Join-Path $testRoot "missing-gallery-binding.csv"
  Write-Utf8Csv -Path $missingGalleryBindingPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/detail.jpg,2,https://example.com/blue.jpg"
  )

  $nonContiguousColorPath = Join-Path $testRoot "non-contiguous-color.csv"
  Write-Utf8Csv -Path $nonContiguousColorPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "sample-product,,,Blue,,M,SAMPLE-BLUE-M,https://example.com/detail.jpg,3,https://example.com/blue.jpg"
  )

  $simplifiedChineseColor = ([string][char]0x989C) + ([char]0x8272)
  $chineseSourcePath = Join-Path $testRoot "chinese-source.csv"
  Write-Utf8Csv -Path $chineseSourcePath -Lines @(
    $header,
    "sample-product,Sample Product,$simplifiedChineseColor,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )
  $chineseColorOrderMismatchPath = Join-Path $testRoot "chinese-color-order-mismatch.csv"
  Write-Utf8Csv -Path $chineseColorOrderMismatchPath -Lines @(
    $header,
    "sample-product,Sample Product,$simplifiedChineseColor,Blue,Size,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,1,https://example.com/blue.jpg",
    "sample-product,,,Black,,S,SAMPLE-BLACK-S,https://example.com/black.jpg,2,https://example.com/black.jpg"
  )

  $missingFinalColorOptionPath = Join-Path $testRoot "missing-final-color-option.csv"
  Write-Utf8Csv -Path $missingFinalColorOptionPath -Lines @(
    $header,
    "sample-product,Sample Product,,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )

  $renamedHandlePath = Join-Path $testRoot "renamed-handle.csv"
  Write-Utf8Csv -Path $renamedHandlePath -Lines @(
    $header,
    "renamed-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "renamed-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/black.jpg",
    "renamed-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )

  $sourceWithoutColorPath = Join-Path $testRoot "source-without-color.csv"
  Write-Utf8Csv -Path $sourceWithoutColorPath -Lines @(
    $header,
    "sample-product,Sample Product,,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,1,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )

  $caseSensitiveUrlSourcePath = Join-Path $testRoot "case-sensitive-url-source.csv"
  Write-Utf8Csv -Path $caseSensitiveUrlSourcePath -Lines @(
    $header,
    "case-product,Case Product,Color,Black,Size,S,CASE-BLACK-S,https://example.com/A.jpg,1,https://example.com/A.jpg",
    "case-product,,,Blue,,S,CASE-BLUE-S,https://example.com/a.jpg,2,https://example.com/a.jpg"
  )
  $caseSensitiveUrlValidPath = Join-Path $testRoot "case-sensitive-url-valid.csv"
  Copy-Item -LiteralPath $caseSensitiveUrlSourcePath -Destination $caseSensitiveUrlValidPath
  $caseSensitiveUrlMismatchPath = Join-Path $testRoot "case-sensitive-url-mismatch.csv"
  Write-Utf8Csv -Path $caseSensitiveUrlMismatchPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/A.jpg,1,https://example.com/A.jpg",
    "sample-product,,,Black,,M,SAMPLE-BLACK-M,,,https://example.com/a.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )

  $oversizedImagePositionPath = Join-Path $testRoot "oversized-image-position.csv"
  Write-Utf8Csv -Path $oversizedImagePositionPath -Lines @(
    $header,
    "sample-product,Sample Product,Color,Black,Size,S,SAMPLE-BLACK-S,https://example.com/black.jpg,999999999999,https://example.com/black.jpg",
    "sample-product,,,Blue,,S,SAMPLE-BLUE-S,https://example.com/blue.jpg,2,https://example.com/blue.jpg"
  )

  $noColorHeader = "Handle,Title,Option1 Name,Option1 Value,Variant SKU,Image Src,Image Position,Variant Image"
  $noColorSourcePath = Join-Path $testRoot "no-color-source.csv"
  Write-Utf8Csv -Path $noColorSourcePath -Lines @(
    $noColorHeader,
    "default-product,Default Product,Title,Default Title,DEFAULT-SKU,https://example.com/default.jpg,1,https://example.com/default.jpg"
  )
  $noColorMissingGalleryPath = Join-Path $testRoot "no-color-missing-gallery.csv"
  Write-Utf8Csv -Path $noColorMissingGalleryPath -Lines @(
    $noColorHeader,
    "default-product,Default Product,Title,Default Title,DEFAULT-SKU,https://example.com/default.jpg,1,https://example.com/missing.jpg"
  )

  $results = @(
    Invoke-ValidationCase -Name "valid" -CsvPath $validPath -SourceCsvPath $sourcePath -ExpectedExitCode 0
    Invoke-ValidationCase -Name "missing-position-one" -CsvPath $missingPositionOnePath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "image_positions_not_contiguous"
    Invoke-ValidationCase -Name "featured-mismatch" -CsvPath $featuredMismatchPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "featured_image_not_first_color"
    Invoke-ValidationCase -Name "color-order-mismatch" -CsvPath $colorOrderMismatchPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "color_order_changed"
    Invoke-ValidationCase -Name "inconsistent-binding" -CsvPath $inconsistentBindingPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "color_has_multiple_variant_images"
    Invoke-ValidationCase -Name "blank-image-position" -CsvPath $blankImagePositionPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "invalid_image_position"
    Invoke-ValidationCase -Name "blank-variant-image" -CsvPath $blankVariantImagePath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "color_has_blank_variant_images"
    Invoke-ValidationCase -Name "missing-gallery-binding" -CsvPath $missingGalleryBindingPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "variant_image_missing_from_gallery"
    Invoke-ValidationCase -Name "non-contiguous-color" -CsvPath $nonContiguousColorPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "color_rows_not_contiguous"
    Invoke-ValidationCase -Name "chinese-color-order-mismatch" -CsvPath $chineseColorOrderMismatchPath -SourceCsvPath $chineseSourcePath -ExpectedExitCode 1 -ExpectedIssueCode "color_order_changed"
    Invoke-ValidationCase -Name "missing-final-color-option" -CsvPath $missingFinalColorOptionPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "color_option_missing_from_final"
    Invoke-ValidationCase -Name "renamed-handle" -CsvPath $renamedHandlePath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "handle_missing_from_source"
    Invoke-ValidationCase -Name "source-color-option-missing" -CsvPath $validPath -SourceCsvPath $sourceWithoutColorPath -ExpectedExitCode 1 -ExpectedIssueCode "source_color_option_missing"
    Invoke-ValidationCase -Name "case-sensitive-url-valid" -CsvPath $caseSensitiveUrlValidPath -SourceCsvPath $caseSensitiveUrlSourcePath -ExpectedExitCode 0
    Invoke-ValidationCase -Name "case-sensitive-url-mismatch" -CsvPath $caseSensitiveUrlMismatchPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "color_has_multiple_variant_images"
    Invoke-ValidationCase -Name "oversized-image-position" -CsvPath $oversizedImagePositionPath -SourceCsvPath $sourcePath -ExpectedExitCode 1 -ExpectedIssueCode "invalid_image_position"
    Invoke-ValidationCase -Name "no-color-missing-gallery" -CsvPath $noColorMissingGalleryPath -SourceCsvPath $noColorSourcePath -ExpectedExitCode 1 -ExpectedIssueCode "variant_image_missing_from_gallery"
  )

  $results | Format-Table -AutoSize
  Write-Output "All image-order validator tests passed: $($results.Count)/$($results.Count)"
} finally {
  $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
  if ($resolvedTestRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
      [System.IO.Path]::GetFileName($resolvedTestRoot).StartsWith("shopify-image-order-tests-", [System.StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
