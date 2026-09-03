param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,

  [Parameter(Mandatory = $true)]
  [string]$ReportPath,

  [Parameter(Mandatory = $true)]
  [string]$SourceCsvPath
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
    [string]$Label,
    [switch]$Optional
  )

  foreach ($candidate in $Candidates) {
    foreach ($header in $Headers) {
      if ([string]::Equals($header, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $header
      }
    }
  }
  if ($Optional) {
    return $null
  }
  throw "Missing required Shopify CSV column '$Label'. Accepted headers: $($Candidates -join ', ')."
}

function Test-IsColorOptionName {
  param([string]$Value)

  $normalized = $Value.Trim().ToLowerInvariant()
  $simplifiedChineseColor = ([string][char]0x989C) + ([char]0x8272)
  $traditionalChineseColor = ([string][char]0x984F) + ([char]0x8272)
  return $normalized -eq "color" -or
    $normalized -eq "colour" -or
    $normalized.Contains($simplifiedChineseColor) -or
    $normalized.Contains($traditionalChineseColor)
}

function Get-ColorColumns {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Rows,
    [Parameter(Mandatory = $true)]
    [hashtable]$OptionColumns
  )

  foreach ($index in 1..3) {
    $nameColumn = $OptionColumns["Option${index}Name"]
    $valueColumn = $OptionColumns["Option${index}Value"]
    if ([string]::IsNullOrWhiteSpace($nameColumn) -or [string]::IsNullOrWhiteSpace($valueColumn)) {
      continue
    }
    foreach ($row in $Rows) {
      if (Test-IsColorOptionName (Get-CellText -Row $row -Column $nameColumn)) {
        return [pscustomobject]@{
          NameColumn = $nameColumn
          ValueColumn = $valueColumn
        }
      }
    }
  }
  return $null
}

function Get-OrderedUniqueValues {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Rows,
    [Parameter(Mandatory = $true)]
    [string]$Column
  )

  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  $result = New-Object 'System.Collections.Generic.List[string]'
  foreach ($row in $Rows) {
    $value = Get-CellText -Row $row -Column $Column
    if ($value -and $seen.Add($value)) {
      $result.Add($value)
    }
  }
  return $result.ToArray()
}

function Test-SequenceEqual {
  param(
    [string[]]$Left,
    [string[]]$Right
  )

  if ($Left.Count -ne $Right.Count) {
    return $false
  }
  for ($index = 0; $index -lt $Left.Count; $index++) {
    if (-not [string]::Equals($Left[$index], $Right[$index], [System.StringComparison]::OrdinalIgnoreCase)) {
      return $false
    }
  }
  return $true
}

function Test-SequenceEqualOrdinal {
  param(
    [string[]]$Left,
    [string[]]$Right
  )

  if ($Left.Count -ne $Right.Count) {
    return $false
  }
  for ($index = 0; $index -lt $Left.Count; $index++) {
    if (-not [string]::Equals($Left[$index], $Right[$index], [System.StringComparison]::Ordinal)) {
      return $false
    }
  }
  return $true
}

function New-ValidationIssue {
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

function Import-ShopifyCsv {
  param([Parameter(Mandatory = $true)][string]$Path)

  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "CSV file not found: $resolved"
  }
  $rows = @(Import-Csv -LiteralPath $resolved -Encoding UTF8)
  if ($rows.Count -eq 0) {
    throw "CSV contains no data rows: $resolved"
  }
  return [pscustomobject]@{
    Path = $resolved
    Rows = $rows
    Headers = @($rows[0].PSObject.Properties.Name)
  }
}

$csv = Import-ShopifyCsv -Path $CsvPath
$handleColumn = Resolve-Column -Headers $csv.Headers -Candidates @("Handle") -Label "Handle"
$imageUrlColumn = Resolve-Column -Headers $csv.Headers -Candidates @("Image Src", "Product image URL") -Label "Image Src"
$imagePositionColumn = Resolve-Column -Headers $csv.Headers -Candidates @("Image Position", "Image position") -Label "Image Position"
$variantImageColumn = Resolve-Column -Headers $csv.Headers -Candidates @("Variant Image", "Variant image") -Label "Variant Image"

$optionColumns = @{}
foreach ($index in 1..3) {
  $optionColumns["Option${index}Name"] = Resolve-Column -Headers $csv.Headers -Candidates @("Option${index} Name") -Label "Option${index} Name" -Optional
  $optionColumns["Option${index}Value"] = Resolve-Column -Headers $csv.Headers -Candidates @("Option${index} Value") -Label "Option${index} Value" -Optional
}

$fileIssues = New-Object 'System.Collections.Generic.List[object]'
$sourceGalleryOrders = @{}
$sourceColorOrders = @{}
$sourceColorImageMaps = @{}
$sourceHandles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$sourceCsv = Import-ShopifyCsv -Path $SourceCsvPath
$resolvedSourcePath = $sourceCsv.Path
$sourceHandleColumn = Resolve-Column -Headers $sourceCsv.Headers -Candidates @("Handle") -Label "Handle"
$sourceImageUrlColumn = Resolve-Column -Headers $sourceCsv.Headers -Candidates @("Image Src", "Product image URL") -Label "Image Src"
$sourceImagePositionColumn = Resolve-Column -Headers $sourceCsv.Headers -Candidates @("Image Position", "Image position") -Label "Image Position"
$sourceVariantImageColumn = Resolve-Column -Headers $sourceCsv.Headers -Candidates @("Variant Image", "Variant image") -Label "Variant Image"
$sourceOptionColumns = @{}
foreach ($index in 1..3) {
  $sourceOptionColumns["Option${index}Name"] = Resolve-Column -Headers $sourceCsv.Headers -Candidates @("Option${index} Name") -Label "Option${index} Name" -Optional
  $sourceOptionColumns["Option${index}Value"] = Resolve-Column -Headers $sourceCsv.Headers -Candidates @("Option${index} Value") -Label "Option${index} Value" -Optional
}
foreach ($sourceGroup in ($sourceCsv.Rows | Group-Object { Get-CellText -Row $_ -Column $sourceHandleColumn })) {
  if (-not $sourceGroup.Name) {
    continue
  }
  [void]$sourceHandles.Add($sourceGroup.Name)
  $sourceKey = $sourceGroup.Name.ToLowerInvariant()
  $sourceRows = @($sourceGroup.Group)
  $sourceImageRows = @($sourceRows | Where-Object { Get-CellText -Row $_ -Column $sourceImageUrlColumn })
  $sourcePositionRecords = New-Object 'System.Collections.Generic.List[object]'
  foreach ($sourceImageRow in $sourceImageRows) {
    $sourceUrl = Get-CellText -Row $sourceImageRow -Column $sourceImageUrlColumn
    $sourcePositionText = Get-CellText -Row $sourceImageRow -Column $sourceImagePositionColumn
    $sourcePosition = 0
    if ($sourcePositionText -notmatch '^[1-9][0-9]*$' -or -not [int]::TryParse($sourcePositionText, [ref]$sourcePosition)) {
      $fileIssues.Add((New-ValidationIssue -Code "source_invalid_image_position" -Message "Source product '$($sourceGroup.Name)' has an image with an invalid Image Position, so main-site gallery order cannot be verified." -Details @{ handle = $sourceGroup.Name; imageUrl = $sourceUrl; value = $sourcePositionText }))
      continue
    }
    $sourcePositionRecords.Add([pscustomobject]@{ position = $sourcePosition; url = $sourceUrl })
  }
  if ($sourceImageRows.Count -eq 0) {
    $fileIssues.Add((New-ValidationIssue -Code "source_product_has_no_images" -Message "Source product '$($sourceGroup.Name)' has no Image Src rows, so main-site gallery order cannot be verified." -Details @{ handle = $sourceGroup.Name }))
  }
  if ($sourcePositionRecords.Count -eq $sourceImageRows.Count -and $sourceImageRows.Count -gt 0) {
    foreach ($duplicatePositionGroup in @($sourcePositionRecords | Group-Object position | Where-Object { $_.Count -gt 1 })) {
      $fileIssues.Add((New-ValidationIssue -Code "source_duplicate_image_position" -Message "Source product '$($sourceGroup.Name)' has duplicate Image Position '$($duplicatePositionGroup.Name)', so main-site gallery order is ambiguous." -Details @{ handle = $sourceGroup.Name; position = [int]$duplicatePositionGroup.Name; imageUrls = @($duplicatePositionGroup.Group | ForEach-Object { $_.url }) }))
    }
  }
  $sourceGalleryOrder = @($sourcePositionRecords | Sort-Object position | ForEach-Object { $_.url })
  $sourceGalleryOrders[$sourceKey] = $sourceGalleryOrder
  $sourceGalleryUrlSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($sourceGalleryUrl in $sourceGalleryOrder) {
    [void]$sourceGalleryUrlSet.Add($sourceGalleryUrl)
  }

  $sourceColorColumns = Get-ColorColumns -Rows $sourceRows -OptionColumns $sourceOptionColumns
  if ($null -ne $sourceColorColumns) {
    $sourceColors = @(Get-OrderedUniqueValues -Rows $sourceRows -Column $sourceColorColumns.ValueColumn)
    $sourceColorImageMap = [ordered]@{}
    foreach ($sourceColor in $sourceColors) {
      $sourceColorRows = @($sourceRows | Where-Object { [string]::Equals((Get-CellText -Row $_ -Column $sourceColorColumns.ValueColumn), $sourceColor, [System.StringComparison]::OrdinalIgnoreCase) })
      $sourceVariantImageSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
      $sourceVariantImageList = New-Object 'System.Collections.Generic.List[string]'
      foreach ($sourceColorRow in $sourceColorRows) {
        $sourceVariantImage = Get-CellText -Row $sourceColorRow -Column $sourceVariantImageColumn
        if ($sourceVariantImage -and $sourceVariantImageSet.Add($sourceVariantImage)) {
          $sourceVariantImageList.Add($sourceVariantImage)
        }
      }
      $sourceVariantImages = $sourceVariantImageList.ToArray()
      if ($sourceVariantImages.Count -ne 1) {
        $fileIssues.Add((New-ValidationIssue -Code "source_color_variant_image_invalid" -Message "Source product '$($sourceGroup.Name)' color '$sourceColor' must have exactly one Variant Image before its main-site SKU order can be derived." -Details @{ handle = $sourceGroup.Name; color = $sourceColor; images = @($sourceVariantImages) }))
        continue
      }
      $sourceColorImageMap[$sourceColor] = $sourceVariantImages[0]
      if (-not $sourceGalleryUrlSet.Contains($sourceVariantImages[0])) {
        $fileIssues.Add((New-ValidationIssue -Code "source_variant_image_missing_from_gallery" -Message "Source product '$($sourceGroup.Name)' color '$sourceColor' has a Variant Image that is absent from its Image Src gallery." -Details @{ handle = $sourceGroup.Name; color = $sourceColor; imageUrl = $sourceVariantImages[0] }))
      }
    }

    $derivedSourceColorOrder = New-Object 'System.Collections.Generic.List[string]'
    foreach ($sourceGalleryImage in $sourceGalleryOrder) {
      $matchingColors = @($sourceColors | Where-Object { $sourceColorImageMap.Contains($_) -and [string]::Equals([string]$sourceColorImageMap[$_], $sourceGalleryImage, [System.StringComparison]::Ordinal) })
      if ($matchingColors.Count -gt 1) {
        $fileIssues.Add((New-ValidationIssue -Code "source_variant_image_shared_by_colors" -Message "Source product '$($sourceGroup.Name)' assigns one Variant Image to multiple colors, so main-site SKU order is ambiguous." -Details @{ handle = $sourceGroup.Name; imageUrl = $sourceGalleryImage; colors = @($matchingColors) }))
      }
      foreach ($matchingColor in $matchingColors) {
        if (-not $derivedSourceColorOrder.Contains($matchingColor)) {
          $derivedSourceColorOrder.Add($matchingColor)
        }
      }
    }
    $missingDerivedColors = @($sourceColors | Where-Object { -not $derivedSourceColorOrder.Contains($_) })
    if ($missingDerivedColors.Count -gt 0) {
      $fileIssues.Add((New-ValidationIssue -Code "source_color_order_not_derivable" -Message "Source product '$($sourceGroup.Name)' has colors whose SKU order cannot be derived from Image Position and Variant Image." -Details @{ handle = $sourceGroup.Name; colors = @($missingDerivedColors) }))
    }
    $sourceColorOrders[$sourceKey] = $derivedSourceColorOrder.ToArray()
    $sourceColorImageMaps[$sourceKey] = $sourceColorImageMap
  }
}

$closedHandles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$lastHandle = ""
foreach ($row in $csv.Rows) {
  $handle = Get-CellText -Row $row -Column $handleColumn
  if (-not $handle) {
    $fileIssues.Add((New-ValidationIssue -Code "blank_handle" -Message "Every Shopify product and image row must include Handle."))
    continue
  }
  if ($lastHandle -and -not [string]::Equals($lastHandle, $handle, [System.StringComparison]::OrdinalIgnoreCase)) {
    [void]$closedHandles.Add($lastHandle)
  }
  if ($closedHandles.Contains($handle)) {
    $fileIssues.Add((New-ValidationIssue -Code "handle_rows_not_contiguous" -Message "Rows for handle '$handle' are split into multiple blocks; sorting a Shopify CSV can detach images." -Details @{ handle = $handle }))
  }
  $lastHandle = $handle
}

$productResults = New-Object 'System.Collections.Generic.List[object]'
foreach ($group in ($csv.Rows | Group-Object { Get-CellText -Row $_ -Column $handleColumn })) {
  $handle = $group.Name
  if (-not $handle) {
    continue
  }

  $rows = @($group.Group)
  $issues = New-Object 'System.Collections.Generic.List[object]'
  $sourceKey = $handle.ToLowerInvariant()
  $sourceHasHandle = $sourceHandles.Contains($handle)
  $imageRows = @($rows | Where-Object { Get-CellText -Row $_ -Column $imageUrlColumn })
  $positionValues = New-Object 'System.Collections.Generic.List[int]'
  $positionRecords = New-Object 'System.Collections.Generic.List[object]'

  if ($imageRows.Count -eq 0) {
    $issues.Add((New-ValidationIssue -Code "product_has_no_images" -Message "Product '$handle' has no Image Src rows."))
  }

  foreach ($imageRow in $imageRows) {
    $url = Get-CellText -Row $imageRow -Column $imageUrlColumn
    $positionText = Get-CellText -Row $imageRow -Column $imagePositionColumn
    $position = 0
    if ($positionText -notmatch '^[1-9][0-9]*$' -or -not [int]::TryParse($positionText, [ref]$position)) {
      $issues.Add((New-ValidationIssue -Code "invalid_image_position" -Message "Product '$handle' has an image with a blank, zero, non-integer, or out-of-range Image Position." -Details @{ imageUrl = $url; value = $positionText }))
      continue
    }
    $positionValues.Add($position)
    $positionRecords.Add([pscustomobject]@{ position = $position; url = $url })
  }

  if ($imageRows.Count -gt 0 -and $positionValues.Count -eq $imageRows.Count) {
    $actualPositions = @($positionValues | Sort-Object)
    $expectedPositions = @(1..$imageRows.Count)
    if (($actualPositions -join ",") -ne ($expectedPositions -join ",")) {
      $issues.Add((New-ValidationIssue -Code "image_positions_not_contiguous" -Message "Product '$handle' Image Position values must be unique and continuous from 1 to N." -Details @{ actual = @($actualPositions); expected = @($expectedPositions) }))
    }
  }

  $imageUrlCounts = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
  foreach ($imageRow in $imageRows) {
    $imageUrl = Get-CellText -Row $imageRow -Column $imageUrlColumn
    if ($imageUrlCounts.ContainsKey($imageUrl)) {
      $imageUrlCounts[$imageUrl]++
    } else {
      $imageUrlCounts.Add($imageUrl, 1)
    }
  }
  foreach ($imageUrlCount in $imageUrlCounts.GetEnumerator()) {
    if ($imageUrlCount.Value -gt 1) {
      $issues.Add((New-ValidationIssue -Code "duplicate_product_image_url" -Message "Product '$handle' repeats the same Image Src URL." -Details @{ imageUrl = $imageUrlCount.Key; count = $imageUrlCount.Value }))
    }
  }

  $galleryOrder = @($positionRecords | Sort-Object position | ForEach-Object { $_.url })
  $sourceGalleryOrder = @()
  if ($sourceHasHandle -and $sourceGalleryOrders.ContainsKey($sourceKey)) {
    $sourceGalleryOrder = @($sourceGalleryOrders[$sourceKey])
    if ($positionRecords.Count -eq $imageRows.Count) {
      $sourceGallerySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
      foreach ($sourceGalleryImage in $sourceGalleryOrder) {
        [void]$sourceGallerySet.Add($sourceGalleryImage)
      }
      $finalGallerySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
      foreach ($galleryImage in $galleryOrder) {
        [void]$finalGallerySet.Add($galleryImage)
      }
      $unexpectedGalleryImages = @($galleryOrder | Where-Object { -not $sourceGallerySet.Contains($_) })
      $expectedGalleryOrder = @($sourceGalleryOrder | Where-Object { $finalGallerySet.Contains($_) })
      if ($unexpectedGalleryImages.Count -gt 0 -or -not (Test-SequenceEqualOrdinal -Left $galleryOrder -Right $expectedGalleryOrder)) {
        $issues.Add((New-ValidationIssue -Code "gallery_order_changed" -Message "Product '$handle' gallery must preserve the source CSV Image Position order after any approved image filtering." -Details @{ actual = @($galleryOrder); expected = @($expectedGalleryOrder); unexpected = @($unexpectedGalleryImages) }))
      }
    }
  }

  $galleryUrls = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($imageRow in $imageRows) {
    [void]$galleryUrls.Add((Get-CellText -Row $imageRow -Column $imageUrlColumn))
  }
  $allVariantImageSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  $allVariantImageList = New-Object 'System.Collections.Generic.List[string]'
  foreach ($row in $rows) {
    $variantImage = Get-CellText -Row $row -Column $variantImageColumn
    if ($variantImage -and $allVariantImageSet.Add($variantImage)) {
      $allVariantImageList.Add($variantImage)
    }
  }
  $allVariantImages = $allVariantImageList.ToArray()
  foreach ($variantImage in $allVariantImages) {
    if (-not $galleryUrls.Contains($variantImage)) {
      $issues.Add((New-ValidationIssue -Code "variant_image_missing_from_gallery" -Message "Product '$handle' has a Variant Image that is absent from Image Src." -Details @{ imageUrl = $variantImage }))
    }
  }

  $colorColumns = Get-ColorColumns -Rows $rows -OptionColumns $optionColumns
  $colorOrder = @()
  $sourceColorOrder = @()
  $featuredImage = ""
  $firstColorVariantImage = ""
  $sourceHasColor = $sourceColorOrders.ContainsKey($sourceKey)
  if (-not $sourceHasHandle) {
    $issues.Add((New-ValidationIssue -Code "handle_missing_from_source" -Message "Product '$handle' is absent from the source CSV, so gallery and Color/SKC order preservation cannot be verified."))
  } elseif ($null -eq $colorColumns -and $sourceHasColor) {
    $issues.Add((New-ValidationIssue -Code "color_option_missing_from_final" -Message "Product '$handle' has a Color option in the source CSV but the final CSV no longer identifies one."))
  } elseif ($null -ne $colorColumns -and -not $sourceHasColor) {
    $issues.Add((New-ValidationIssue -Code "source_color_option_missing" -Message "Product '$handle' has a Color option in the final CSV but no verifiable Color option in the source CSV."))
  }
  $positionOneRecords = @($positionRecords | Where-Object { $_.position -eq 1 })
  if ($positionOneRecords.Count -eq 1) {
    $featuredImage = $positionOneRecords[0].url
  }

  if ($null -ne $colorColumns) {
    $colorOrder = @(Get-OrderedUniqueValues -Rows $rows -Column $colorColumns.ValueColumn)
    $collapsedColorOrder = New-Object 'System.Collections.Generic.List[string]'
    $previousColor = ""
    foreach ($row in $rows) {
      $color = Get-CellText -Row $row -Column $colorColumns.ValueColumn
      if ($color -and -not [string]::Equals($color, $previousColor, [System.StringComparison]::OrdinalIgnoreCase)) {
        $collapsedColorOrder.Add($color)
        $previousColor = $color
      }
    }
    if ($collapsedColorOrder.Count -ne $colorOrder.Count) {
      $issues.Add((New-ValidationIssue -Code "color_rows_not_contiguous" -Message "Product '$handle' variants are not grouped into one contiguous block per color." -Details @{ sequence = $collapsedColorOrder.ToArray() }))
    }

    if ($sourceHasColor) {
      $sourceColors = @($sourceColorOrders[$sourceKey])
      $sourceColorOrder = @($sourceColors | Where-Object { $colorOrder -contains $_ })
      $unexpectedColors = @($colorOrder | Where-Object { $sourceColors -notcontains $_ })
      if ($unexpectedColors.Count -gt 0 -or -not (Test-SequenceEqual -Left $colorOrder -Right $sourceColorOrder)) {
        $issues.Add((New-ValidationIssue -Code "color_order_changed" -Message "Product '$handle' Color option order must match the order of its Variant Images in the source Image Position gallery; SKC thumbnails would otherwise differ from the main site." -Details @{ actual = @($colorOrder); expected = @($sourceColorOrder); unexpected = @($unexpectedColors) }))
      }
    }

    $colorImageMap = [ordered]@{}
    foreach ($color in $colorOrder) {
      $colorRows = @($rows | Where-Object { [string]::Equals((Get-CellText -Row $_ -Column $colorColumns.ValueColumn), $color, [System.StringComparison]::OrdinalIgnoreCase) })
      $blankBindings = @($colorRows | Where-Object { -not (Get-CellText -Row $_ -Column $variantImageColumn) })
      $variantImageSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
      $variantImageList = New-Object 'System.Collections.Generic.List[string]'
      foreach ($colorRow in $colorRows) {
        $variantImageValue = Get-CellText -Row $colorRow -Column $variantImageColumn
        if ($variantImageValue -and $variantImageSet.Add($variantImageValue)) {
          $variantImageList.Add($variantImageValue)
        }
      }
      $variantImages = $variantImageList.ToArray()

      if ($blankBindings.Count -gt 0) {
        $issues.Add((New-ValidationIssue -Code "color_has_blank_variant_images" -Message "Product '$handle' color '$color' has variants without Variant Image." -Details @{ blankVariantCount = $blankBindings.Count; variantCount = $colorRows.Count }))
      }
      if ($variantImages.Count -ne 1) {
        $issues.Add((New-ValidationIssue -Code "color_has_multiple_variant_images" -Message "Product '$handle' color '$color' must use exactly one Variant Image across all sizes." -Details @{ images = @($variantImages) }))
      } else {
        $variantImage = $variantImages[0]
        $colorImageMap[$color] = $variantImage
      }
    }

    if ($sourceHasColor -and $sourceColorImageMaps.ContainsKey($sourceKey)) {
      $sourceColorImageMap = $sourceColorImageMaps[$sourceKey]
      foreach ($color in $colorOrder) {
        if ($sourceColorImageMap.Contains($color) -and $colorImageMap.Contains($color)) {
          $expectedVariantImage = [string]$sourceColorImageMap[$color]
          $actualVariantImage = [string]$colorImageMap[$color]
          if (-not [string]::Equals($actualVariantImage, $expectedVariantImage, [System.StringComparison]::Ordinal)) {
            $issues.Add((New-ValidationIssue -Code "variant_image_binding_changed" -Message "Product '$handle' color '$color' Variant Image changed from the source CSV." -Details @{ color = $color; actual = $actualVariantImage; expected = $expectedVariantImage }))
          }
        }
      }
    }

    if ($colorOrder.Count -gt 0 -and $colorImageMap.Contains($colorOrder[0])) {
      $firstColorVariantImage = [string]$colorImageMap[$colorOrder[0]]
    }
  }

  $productResults.Add([pscustomobject]@{
    handle = $handle
    passed = $issues.Count -eq 0
    imageCount = $imageRows.Count
    imagePositions = @($positionValues.ToArray() | Sort-Object)
    featuredImage = $featuredImage
    galleryOrder = @($galleryOrder)
    sourceGalleryOrder = @($sourceGalleryOrder)
    colorOrder = @($colorOrder)
    sourceColorOrder = @($sourceColorOrder)
    firstColorVariantImage = $firstColorVariantImage
    issues = $issues.ToArray()
  })
}

$allIssues = $fileIssues.ToArray() + @($productResults | ForEach-Object { $_.issues })
$issueCounts = [ordered]@{}
foreach ($issueGroup in ($allIssues | Group-Object code | Sort-Object Name)) {
  $issueCounts[$issueGroup.Name] = $issueGroup.Count
}

$resolvedReportPath = [System.IO.Path]::GetFullPath($ReportPath)
$reportDirectory = Split-Path -Parent $resolvedReportPath
if ($reportDirectory) {
  New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
}

$report = [ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  csvPath = $csv.Path
  sourceCsvPath = $resolvedSourcePath
  passed = $allIssues.Count -eq 0
  summary = [ordered]@{
    productCount = $productResults.Count
    passedProductCount = @($productResults | Where-Object { $_.passed }).Count
    failedProductCount = @($productResults | Where-Object { -not $_.passed }).Count
    fileIssueCount = $fileIssues.Count
    issueCount = $allIssues.Count
    issueCountsByCode = $issueCounts
  }
  fileIssues = $fileIssues.ToArray()
  products = $productResults.ToArray()
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedReportPath -Encoding UTF8

if ($report.passed) {
  Write-Output "PASS: $($csv.Path) ($($productResults.Count) products). Report: $resolvedReportPath"
  exit 0
}

Write-Output "FAIL: $($csv.Path) ($($report.summary.failedProductCount) failed products, $($report.summary.issueCount) issues). Report: $resolvedReportPath"
exit 1
