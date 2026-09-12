param(
    [string]$CapturePreview = "",
    [ValidateSet("front", "side", "back", "detail")]
    [string]$View = "front",
    [ValidateRange(-1, 2)]
    [int]$Lod = -1
)

$ErrorActionPreference = 'Stop'
$godotCommand = Get-Command godot_console.exe -ErrorAction SilentlyContinue
if ($null -eq $godotCommand) { $godotCommand = Get-Command godot.exe }
$projectRoot = Split-Path -Parent $PSScriptRoot
& $godotCommand.Source --headless --editor --path $projectRoot --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$previewArguments = @('--path', $projectRoot, '--resolution', '1440x1000', 'res://scenes/preview/tree_pack_preview.tscn', '--', '--farm-test', "--view=$View", "--lod=$Lod")
if ($CapturePreview) { $previewArguments += "--capture-preview=$CapturePreview" }
& $godotCommand.Source @previewArguments
exit $LASTEXITCODE
