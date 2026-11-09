$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
cmake -S Kernel -B build-native
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build build-native --config Release --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
ctest --test-dir build-native --config Release --output-on-failure
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$env:PYTHONPATH = 'Toolkit'
$env:AEROSPATIAL_NATIVE_PROBE = (Resolve-Path 'build-native/Release/aerospatial-native-probe.exe').Path
python -m unittest discover -s ToolkitTests -v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python -m aerospatial_tools validate Fixtures/session.jsonl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$sample = Join-Path $env:TEMP 'aerospatial-native-quality.jsonl'
try {
    python -m aerospatial_tools simulate $sample --seconds 5 --seed 42
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    python -m aerospatial_tools gate $sample --profile Quality/simulator.json
    exit $LASTEXITCODE
} finally { Remove-Item $sample -ErrorAction SilentlyContinue }
