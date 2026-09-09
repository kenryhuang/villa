param([string]$Godot = 'godot_console.exe')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $null = Get-Command $Godot -ErrorAction Stop
    if (-not (Test-Path -LiteralPath 'tmp/living-world/P12-live-2.json')) {
        throw '先运行 P12 -LiveAgents，生成第二个真实模型观察窗口作为回放来源。'
    }
    foreach ($group in @('rules', 'private', 'public')) {
        foreach ($seed in @(42, 93, 137)) {
            & $Godot --headless --path . --script tests/run_living_world_economy_benchmark.gd -- --farm-test --living-world-scenario=P12 "--group=$group" "--seed=$seed"
            if ($LASTEXITCODE -ne 0) { throw "Failed: $group seed $seed" }
            $report = Get-Content -LiteralPath "tmp/living-world/P12-economy-$group-$seed.json" -Raw | ConvertFrom-Json
            if ($report.batch_p95_us -gt 4000 -or $report.frame_max_us -gt 8000) { throw "Performance budget exceeded: $group seed $seed" }
        }
    }
    foreach ($strategy in @('farmer', 'trader')) {
        & $Godot --headless --path . --script tests/run_living_world_economy_benchmark.gd -- --farm-test --living-world-scenario=P12 --group=rules --seed=42 "--strategy=$strategy"
        if ($LASTEXITCODE -ne 0) { throw "Failed: player strategy $strategy" }
    }
    Write-Host 'PASS: nine economic comparisons and two player strategies, 28 days each; see tmp/living-world.'
} finally { Pop-Location }
