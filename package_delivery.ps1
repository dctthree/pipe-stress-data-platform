param(
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'deliverables'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$codeZip = Join-Path $OutputDirectory 'stress_data_platform_code_v0.3.0.zip'
if (Test-Path -LiteralPath $codeZip) {
    throw "交付包已存在，请先人工归档或改名：$codeZip"
}
# Archive only committed files. This prevents ignored raw/, runtime/, lake/
# and local release-staging trees (including junctions) from entering a code
# delivery merely because they exist beside the source checkout.
& git -C $root archive --format=zip --output=$codeZip HEAD
if ($LASTEXITCODE -ne 0) {
    throw "git archive failed with exit code $LASTEXITCODE"
}

$indexPath = Join-Path $root 'lake\dataset_index.json'
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$safeVersion = $index.dataset_version -replace '[^A-Za-z0-9._+-]', '_'
$stage = Join-Path $OutputDirectory ("P110_EXP2_full_release_" + $safeVersion)
if (Test-Path -LiteralPath $stage) {
    throw "标准数据交付目录已存在，请先人工归档或改名：$stage"
}
New-Item -ItemType Directory -Path $stage | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'catalog'),(Join-Path $stage 'gold'),(Join-Path $stage 'raw'),(Join-Path $stage 'silver\signals'),(Join-Path $stage 'silver\strain'),(Join-Path $stage 'releases'),(Join-Path $stage 'docs') -Force | Out-Null
Copy-Item -LiteralPath $indexPath -Destination (Join-Path $stage 'dataset_index.json')
Copy-Item -Path (Join-Path $root 'lake\catalog\*') -Destination (Join-Path $stage 'catalog') -Recurse
Copy-Item -Path (Join-Path $root 'lake\gold\*') -Destination (Join-Path $stage 'gold') -Recurse
Copy-Item -Path (Join-Path $root 'lake\raw\*') -Destination (Join-Path $stage 'raw') -Recurse
Copy-Item -LiteralPath (Join-Path $root ('lake\releases\' + $index.dataset_version)) -Destination (Join-Path $stage 'releases') -Recurse
Copy-Item -LiteralPath (Join-Path $root 'docs\AI_DATA_CONTRACT.md') -Destination (Join-Path $stage 'docs')
Copy-Item -LiteralPath (Join-Path $root '系统构建与数据验收报告.md') -Destination $stage

$scanRows = Import-Csv -LiteralPath (Join-Path $root 'lake\catalog\scans.csv')
foreach ($row in $scanRows) {
    $source = Join-Path (Join-Path $root 'lake') ($row.silver_signal_path -replace '/', '\')
    $relativeDirectory = Split-Path -Parent $row.silver_signal_path
    $targetDirectory = Join-Path $stage ($relativeDirectory -replace '/', '\')
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $targetDirectory
}
$strainRows = Import-Csv -LiteralPath (Join-Path $root 'lake\catalog\strain_files.csv')
foreach ($row in $strainRows) {
    $source = Join-Path (Join-Path $root 'lake') ($row.silver_strain_path -replace '/', '\')
    $relativeDirectory = Split-Path -Parent $row.silver_strain_path
    $targetDirectory = Join-Path $stage ($relativeDirectory -replace '/', '\')
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $targetDirectory
}

$dataZip = $stage + '.zip'
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $dataZip -CompressionLevel Optimal
Get-FileHash -LiteralPath $codeZip,$dataZip -Algorithm SHA256 | Format-Table -AutoSize
