param(
    [ValidateSet('P0', 'P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7', 'P8', 'P9', 'P10', 'P11', 'P12')][string]$Stage = 'P0',
    [switch]$IncludeDependencies,
    [switch]$LiveAgents,
    [string]$Godot = 'godot_console.exe'
)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $null = Get-Command $Godot -ErrorAction Stop
    $stageNumber = [int]$Stage.Substring(1)
    $firstStage = if ($IncludeDependencies) { 0 } else { $stageNumber }
    $tests = @($firstStage..$stageNumber | ForEach-Object { "run_living_world_p$($_)_tests.gd" })
    if ($IncludeDependencies) {
        $tests += 'run_agent_trace_recovery_tests.gd'
        $tests += 'run_agent_system_tests.gd', 'run_3d_agent_tests.gd', 'run_production_system_tests.gd', 'run_3d_windmill_tests.gd', 'run_3d_food_workshop_tests.gd', 'run_3d_save_protection_tests.gd'
        $tests += 'run_3d_farm_interaction_tests.gd', 'run_3d_target_system_tests.gd', 'run_3d_farming_tests.gd', 'run_3d_market_tests.gd', 'run_3d_fishing_tests.gd', 'run_3d_golf_tests.gd', 'run_3d_minimap_tests.gd'
    }
    foreach ($test in $tests) {
        if (-not (Test-Path -LiteralPath "tests/$test" -PathType Leaf)) { throw "Missing test: $test" }
        if ($test -eq 'run_living_world_p12_tests.gd') {
            & $Godot --headless --path . --script tests/run_living_world_migration_fixture.gd -- --farm-test
            if ($LASTEXITCODE -ne 0) { throw 'Migration fixture failed' }
            & $Godot --headless --path . --script "tests/$test" -- --farm-test --living-world-scenario=P12
        } else {
            & $Godot --headless --path . --script "tests/$test" -- --farm-test
        }
        if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
    }
    & npm.cmd --prefix services/agent-service test
    if ($LASTEXITCODE -ne 0) { throw 'Agent service tests failed' }
    if ($LiveAgents) {
        if ($stageNumber -le 1) {
            & $Godot --headless --path . --script tests/run_living_world_live_tests.gd -- --living-world-scenario=P0 --living-world-live-agents
        } elseif ($stageNumber -eq 6) {
            & $Godot --headless --path . --script tests/run_living_world_p6_live_tests.gd -- --living-world-scenario=P6 --living-world-live-agents
        } elseif ($stageNumber -eq 7) {
            & $Godot --headless --path . --script tests/run_living_world_p7_live_tests.gd -- --living-world-scenario=P7 --living-world-live-agents
        } elseif ($stageNumber -eq 12) {
            foreach ($window in @(1, 2)) {
                & $Godot --headless --path . --script tests/run_living_world_p12_live_tests.gd -- --living-world-scenario=P12 --living-world-live-agents "--window=$window"
                if ($LASTEXITCODE -ne 0) { throw "Real observation window $window failed" }
            }
        } elseif ($stageNumber -ge 8) {
            & $Godot --headless --path . --script "tests/run_living_world_p$($stageNumber)_live_tests.gd" -- "--living-world-scenario=$Stage" --living-world-live-agents
        } elseif ($stageNumber -ge 3) {
            & $Godot --headless --path . --script tests/run_living_world_autonomy_live_tests.gd -- "--living-world-scenario=$Stage" --living-world-live-agents
        }
        if ($LASTEXITCODE -ne 0) { throw 'Real provider acceptance failed' }
    }
    Write-Host "PASS: Living world $Stage"
} finally { Pop-Location }
