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

$previewArguments = @("--path", $root, "--resolution", "1440x960", "res://scenes/preview/farm_3d_preview.tscn")
if ($CapturePreview -or $Overview) { $previewArguments += "--" }
if ($CapturePreview) { $previewArguments += "--capture-preview=$CapturePreview" }
if ($Overview) { $previewArguments += "--capture-overview" }
& $godot.Source @previewArguments
exit $LASTEXITCODE
