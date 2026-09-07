$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/run_farm3d.ps1'
$parseTokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors.Message -join "`n") }
# Load only the pure identity checks; never import the launcher or stop processes.
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$checks = 0
function Assert-Launcher([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
    $script:checks++
}
$projectRoots = @('D:/UnityProject/villa', 'D:/UnityProject/villa/.worktrees/painted-production-buildings', 'D:/Game Projects/villa')
$legacyHealth = [pscustomobject]@{ status = 'ok'; protocol_version = 2; provider = 'configured' }
$currentHealth = [pscustomobject]@{ status = 'ok'; protocol_version = 2; provider = 'configured'; capabilities = @('farm3d_environment', 'rent_production') }
$processInfo = [pscustomobject]@{ Name = 'node.exe'; CommandLine = '"C:\Program Files\nodejs\node.exe" --experimental-strip-types src/server.ts --config config/agent-service.local.json' }
Assert-Launcher (Test-VillaAgentProcess $processInfo $legacyHealth $projectRoots) 'Recognize the original launcher command'
Assert-Launcher (-not (Test-AgentServiceHealth $legacyHealth)) 'Legacy health must trigger replacement'
Assert-Launcher (Test-AgentServiceHealth $currentHealth) 'Current service can be reused'
$partialHealth = [pscustomobject]@{ status = 'ok'; protocol_version = 2; capabilities = @('rent_production') }
Assert-Launcher (-not (Test-AgentServiceHealth $partialHealth)) 'Require both environment and rental capabilities'
$processInfo.CommandLine = 'node.exe --experimental-strip-types src/server.ts --config "D:/UnityProject/villa/.worktrees/painted-production-buildings/services/agent-service/config/agent-service.local.json"'
Assert-Launcher (Test-VillaAgentProcess $processInfo $legacyHealth $projectRoots) 'Recognize current launcher referencing worktree config'
$processInfo.CommandLine = 'node.exe "D:/Game Projects/villa/services/agent-service/src/server.ts" --config "D:/Game Projects/villa/services/agent-service/config/agent-service.local.json"'
Assert-Launcher (Test-VillaAgentProcess $processInfo $legacyHealth $projectRoots) 'Recognize quoted project paths with spaces'
$processInfo.CommandLine = 'node.exe D:/OtherApp/src/server.ts --config config/agent-service.local.json'
Assert-Launcher (-not (Test-VillaAgentProcess $processInfo $legacyHealth $projectRoots)) 'Never stop another application entry point'
$processInfo.CommandLine = 'node.exe src/server.ts --config D:/OtherApp/config/agent-service.local.json'
Assert-Launcher (-not (Test-VillaAgentProcess $processInfo $legacyHealth $projectRoots)) 'Never stop a process with an unrelated configuration'
$processInfo.CommandLine = 'node.exe src/server.ts'
Assert-Launcher (-not (Test-VillaAgentProcess $processInfo $legacyHealth $projectRoots)) 'Unknown configuration is not sufficient process identity'
$processInfo.Name = 'python.exe'
Assert-Launcher (-not (Test-VillaAgentProcess $processInfo $legacyHealth $projectRoots)) 'Never stop a different executable'
Assert-Launcher (-not (Test-AgentServiceHealth $null)) 'Missing health is not ready'

# Exercise the stop entry point with fake listeners/processes, never the live service.
$clientFixture = [System.IO.Path]::GetTempFileName()
$serviceFixture = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -LiteralPath $clientFixture -Value '{"service_url":"http://127.0.0.1:18787"}'
    Set-Content -LiteralPath $serviceFixture -Value '{"service":{"port":18787}}'
    $global:farmLauncherTestState = @{ Listener = $true; ForeignProcess = $false; StopCalls = 0 }
    function Invoke-RestMethod { param($Uri, $TimeoutSec) return [pscustomobject]@{ status = 'ok'; protocol_version = 2; provider = 'configured' } }
    function Get-NetTCPConnection {
        param($State, $ErrorAction)
        if ($global:farmLauncherTestState.Listener) { [pscustomobject]@{ LocalPort = 18787; LocalAddress = '127.0.0.1'; OwningProcess = 12345 } }
    }
    function Get-CimInstance {
        param($ClassName, $Filter, $ErrorAction)
        $entry = if ($global:farmLauncherTestState.ForeignProcess) { 'D:/OtherApp/src/server.ts' } else { 'src/server.ts' }
        [pscustomobject]@{ Name = 'node.exe'; CommandLine = "node.exe $entry --config config/agent-service.local.json" }
    }
    function Get-Process {
        param($Id, $ErrorAction)
        $fake = [pscustomobject]@{ Id = $Id }
        $fake | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Timeout) return $true }
        return $fake
    }
    function Stop-Process {
        param($InputObject, $Id, $ErrorAction)
        if ($null -eq $InputObject -or $InputObject.Id -ne 12345) { throw 'Unexpected stop target' }
        $global:farmLauncherTestState.StopCalls++
    }
    function Get-Command { throw 'Stop mode must not look up Godot or Node' }
    function Start-Process { throw 'Stop mode must never launch a process' }
    & $scriptPath -StopAgents -AgentClientConfig $clientFixture -AgentServiceConfig $serviceFixture
    Assert-Launcher ($global:farmLauncherTestState.StopCalls -eq 1) 'Stop the recognized listener once'
    $global:farmLauncherTestState.Listener = $false
    & $scriptPath -StopAgents -AgentClientConfig $clientFixture -AgentServiceConfig $serviceFixture
    Assert-Launcher ($global:farmLauncherTestState.StopCalls -eq 1) 'Already stopped is a harmless no-op'
    $global:farmLauncherTestState.Listener = $true
    $global:farmLauncherTestState.ForeignProcess = $true
    $rejected = $false
    try { & $scriptPath -StopAgents -AgentClientConfig $clientFixture -AgentServiceConfig $serviceFixture } catch { $rejected = $true }
    Assert-Launcher ($rejected -and $global:farmLauncherTestState.StopCalls -eq 1) 'Refuse unrelated listeners without stopping them'
    $rejected = $false
    try { & $scriptPath -StopAgents -ServiceOnly } catch { $rejected = $true }
    Assert-Launcher $rejected 'Reject conflicting start and stop options'
} finally {
    Remove-Variable -Name farmLauncherTestState -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $clientFixture, $serviceFixture -ErrorAction SilentlyContinue
}
Write-Output "Farm3D launcher: $checks checks passed"
