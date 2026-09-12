param(
    [ValidateRange(0, 4)] [int]$Tree = 0,
    [ValidateRange(0, 2)] [int]$Lod = 0,
    [switch]$Bare,
    [string]$CapturePreview = ""
)

$ErrorActionPreference = 'Stop'
$godotCommand = Get-Command godot_console.exe -ErrorAction SilentlyContinue
if ($null -eq $godotCommand) { $godotCommand = Get-Command godot.exe }
$projectRoot = Split-Path -Parent $PSScriptRoot
$previewArguments = @('--path', $projectRoot, '--resolution', '1440x1000', 'res://scenes/preview/illustrated_tree_preview.tscn', '--', '--farm-test', "--tree=$Tree", "--lod=$Lod")
if ($Bare) { $previewArguments += '--bare' }
if ($CapturePreview) { $previewArguments += "--capture-preview=$CapturePreview" }
& $godotCommand.Source @previewArguments
exit $LASTEXITCODE
