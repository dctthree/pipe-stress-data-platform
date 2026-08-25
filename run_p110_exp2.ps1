param(
    [string]$PythonExe = 'python',
    [ValidateSet('blob','reference')]
    [string]$SnapshotMode = 'blob'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& $PythonExe (Join-Path $root 'run_pipeline.py') run `
    --config (Join-Path $root 'configs\p110_exp2.json') `
    --output (Join-Path $root 'lake') `
    --snapshot-mode $SnapshotMode
if ($LASTEXITCODE -ne 0) {
    throw "数据链执行失败，退出码 $LASTEXITCODE"
}
