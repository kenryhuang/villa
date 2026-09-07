param(
    [string]$CapturePreview = "",
    [switch]$Overview,
    [switch]$Agents,
    [switch]$CheckAgents,
    [switch]$ServiceOnly,
    [switch]$StopAgents,
    [string]$AgentClientConfig = "",
    [string]$AgentServiceConfig = ""
)

function Test-AgentServiceHealth($Health) {
    return ($null -ne $Health -and $Health.status -eq 'ok' -and $Health.protocol_version -eq 2 -and
        'farm3d_environment' -in $Health.capabilities -and 'rent_production' -in $Health.capabilities)
}

function Test-VillaAgentProcess($ProcessInfo, $Health, [string[]]$ProjectRoots) {
    if ($null -eq $ProcessInfo -or $ProcessInfo.Name -ne 'node.exe' -or
        $Health.status -ne 'ok' -or $Health.protocol_version -ne 2 -or $Health.provider -ne 'configured') { return $false }
    $tokens = @([regex]::Matches($ProcessInfo.CommandLine, '"([^"]*)"|(\S+)') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    })
    $configIndex = [array]::IndexOf($tokens, '--config')
    if ($configIndex -lt 0 -or $configIndex + 1 -ge $tokens.Count) { return $false }
    $configArgument = $tokens[$configIndex + 1].Replace('\', '/')
    $knownScripts = @($ProjectRoots | ForEach-Object { (Join-Path $_ 'services/agent-service/src/server.ts').Replace('\', '/') })
    $knownConfigs = @($ProjectRoots | ForEach-Object { (Join-Path $_ 'services/agent-service/config/agent-service.local.json').Replace('\', '/') })
    $scriptArguments = @($tokens | ForEach-Object { $_.Replace('\', '/') } | Where-Object { $_ -match '\.(ts|js)$' })
    if ($scriptArguments.Count -ne 1) { return $false }
    # The original launcher used precisely these relative entry/config arguments.
    return (($scriptArguments[0] -eq 'src/server.ts' -or $scriptArguments[0] -in $knownScripts) -and
        ($configArgument -eq 'config/agent-service.local.json' -or $configArgument -in $knownConfigs))
}

if ($StopAgents -and ($ServiceOnly -or $CheckAgents -or $CapturePreview -or $Overview)) { throw '-StopAgents 不能与启动、检查或截图选项同时使用。' }
if ($ServiceOnly -and ($CheckAgents -or $CapturePreview)) { throw '-ServiceOnly 不能与 -CheckAgents 或 -CapturePreview 同时使用。' }
if ($CheckAgents -or $ServiceOnly -or $StopAgents) { $Agents = $true }
$root = Split-Path -Parent $PSScriptRoot
if (-not $CheckAgents -and -not $ServiceOnly -and -not $StopAgents) {
    $godot = Get-Command godot_console.exe -ErrorAction SilentlyContinue
    if ($null -eq $godot) {
        $godot = Get-Command godot.exe -ErrorAction Stop
    }

    & $godot.Source --headless --editor --path $root --quit
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$gameArguments = @("--path", $root, "--resolution", "1440x960", "res://scenes/farm3d/main.tscn")
$agentProcess = $null
$keepAgentService = $false
try {
    if ($Agents -and -not $CapturePreview) {
        # Use the existing private configuration in place, including another checkout.
        $configRoots = @($root)
        $configRoots += (& git -C $root worktree list --porcelain | Where-Object { $_.StartsWith('worktree ') } | ForEach-Object { $_.Substring(9) })
        foreach ($configRoot in $configRoots) {
            if (-not $AgentClientConfig) {
                $candidate = Join-Path $configRoot 'config/agent-client.local.json'
                if (Test-Path -LiteralPath $candidate) { $AgentClientConfig = $candidate }
            }
            if (-not $AgentServiceConfig) {
                $candidate = Join-Path $configRoot 'services/agent-service/config/agent-service.local.json'
                if (Test-Path -LiteralPath $candidate) { $AgentServiceConfig = $candidate }
            }
        }
        if (-not $AgentClientConfig -or -not $AgentServiceConfig) {
            throw 'Agent 配置未找到。用 -AgentClientConfig 和 -AgentServiceConfig 指向现有配置文件。'
        }
        $AgentClientConfig = (Resolve-Path -LiteralPath $AgentClientConfig).Path
        $AgentServiceConfig = (Resolve-Path -LiteralPath $AgentServiceConfig).Path
        $clientSettings = Get-Content -LiteralPath $AgentClientConfig -Raw | ConvertFrom-Json
        $healthUrl = $clientSettings.service_url.TrimEnd('/') + '/health'
        $alreadyRunning = $false
        $health = $null
        try { $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2; $alreadyRunning = $true } catch {}
        if ($StopAgents -or ($alreadyRunning -and -not (Test-AgentServiceHealth $health))) {
            $endpoint = [uri]$clientSettings.service_url
            if (-not $endpoint.IsLoopback) { throw '此脚本只能停止或替换本机 Agent 服务。' }
            $serviceSettings = Get-Content -LiteralPath $AgentServiceConfig -Raw | ConvertFrom-Json
            if ($endpoint.Port -ne $serviceSettings.service.port) { throw '客户端端口与服务端配置不一致，未停止任何进程。' }
            $owners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
                Where-Object { $_.LocalPort -eq $endpoint.Port } |
                Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0', '::') } |
                Select-Object -ExpandProperty OwningProcess -Unique)
            if ($StopAgents -and $owners.Count -eq 0) {
                Write-Host "Agent 服务未运行（端口 $($endpoint.Port)）。"
                return
            }
            if ($owners.Count -ne 1) { throw '无法唯一确认旧 Agent 服务进程，未停止任何进程。' }
            $oldInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($owners[0])" -ErrorAction Stop
            if (-not (Test-VillaAgentProcess $oldInfo $health $configRoots)) {
                throw "端口 $($endpoint.Port) 的进程 $($owners[0]) 无法识别为本项目 Agent 服务，未停止该进程。"
            }
            $operation = if ($StopAgents) { '停止' } else { '替换旧' }
            Write-Host "正在$operation Agent 服务（PID $($owners[0])，端口 $($endpoint.Port)）……"
            $oldProcess = Get-Process -Id $owners[0] -ErrorAction Stop
            Stop-Process -InputObject $oldProcess -ErrorAction Stop
            if (-not $oldProcess.WaitForExit(5000)) { throw '旧 Agent 服务尚未退出，请稍后重试。' }
            if ($StopAgents) {
                Write-Host 'Agent 服务已停止。'
                return
            }
            $alreadyRunning = $false
        }
        if (-not $alreadyRunning) {
            $node = Get-Command node.exe -ErrorAction Stop
            $serviceRoot = Join-Path $root 'services/agent-service'
            $agentProcess = Start-Process -FilePath $node.Source -ArgumentList @('--experimental-strip-types', 'src/server.ts', '--config', ('"' + $AgentServiceConfig + '"')) -WorkingDirectory $serviceRoot -WindowStyle Hidden -PassThru
            $ready = $false
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                if ($agentProcess.HasExited) { throw 'Agent 服务启动失败，请检查配置和端口。' }
                try { $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 1; $ready = Test-AgentServiceHealth $health } catch {}
                if ($ready) { break }
                Start-Sleep -Milliseconds 250
            }
            if (-not $ready) {
                Stop-Process -Id $agentProcess.Id -ErrorAction SilentlyContinue
                throw 'Agent 服务未就绪，请检查客户端 service_url 与服务端端口是否一致。'
            }
        }
        Write-Host 'Agent 服务已就绪：地图查询、建筑查询和租用加工可用。'
    }
    if ($CheckAgents) { return }
    if ($ServiceOnly) {
        $keepAgentService = $true
        $processLabel = if ($null -ne $agentProcess) { "（PID $($agentProcess.Id)）" } else { '（复用现有服务）' }
        Write-Host "Agent 服务已在后台运行$processLabel。可自行启动 Godot。"
        return
    }
    if ($CapturePreview -or $Overview -or $AgentClientConfig) { $gameArguments += "--" }
    if ($CapturePreview) { $gameArguments += "--capture-preview=$CapturePreview" }
    if ($Overview) { $gameArguments += "--capture-overview" }
    if ($AgentClientConfig) { $gameArguments += "--agent-client-config=$AgentClientConfig" }
    & $godot.Source @gameArguments
    $gameExit = $LASTEXITCODE
} finally {
    if (-not $keepAgentService -and $null -ne $agentProcess -and -not $agentProcess.HasExited) {
        Stop-Process -Id $agentProcess.Id -ErrorAction SilentlyContinue
    }
}
exit $gameExit
