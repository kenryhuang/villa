param(
    [string]$CapturePreview = "",
    [switch]$Overview
)

$godot = Get-Command godot_console.exe -ErrorAction SilentlyContinue
if ($null -eq $godot) {
    $godot = Get-Command godot.exe -ErrorAction Stop
}

$root = Split-Path -Parent $PSScriptRoot
& $godot.Source --headless --editor --path $root --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$gameArguments = @("--path", $root, "--resolution", "1440x960", "res://scenes/farm3d/main.tscn")
if ($CapturePreview -or $Overview) { $gameArguments += "--" }
if ($CapturePreview) { $gameArguments += "--capture-preview=$CapturePreview" }
if ($Overview) { $gameArguments += "--capture-overview" }
& $godot.Source @gameArguments
exit $LASTEXITCODE
