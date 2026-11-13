$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
python Scripts/check-layout.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake -S Kernel -B build-native -DAEROSPATIAL_BUILD_SOAK=ON -DAEROSPATIAL_BUILD_FUZZ_SMOKE=ON
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build build-native --config Release --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
ctest --test-dir build-native -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& 'build-native/Release/aerospatial-fuzz-smoke.exe'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& 'build-native/Release/aerospatial-soak.exe' 25000
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$env:PYTHONPATH = '.'
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
