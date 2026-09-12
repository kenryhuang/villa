param(
    [ValidateRange(0, 5)][int]$Tree = 0,
    [ValidateRange(0, 2)][int]$Lod = 0,
    [switch]$Bare,
    [string]$CapturePreview = ""
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotCommand = Get-Command godot_console.exe -ErrorAction SilentlyContinue
if ($null -eq $godotCommand) { $godotCommand = Get-Command godot.exe }
& $godotCommand.Source --headless --editor --path $projectRoot --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$previewArguments = @('--path', $projectRoot, '--resolution', '1440x1000', 'res://scenes/preview/diverse_tree_preview.tscn', '--', "--tree=$Tree", "--lod=$Lod")
if ($Bare) { $previewArguments += '--bare' }
if ($CapturePreview) { $previewArguments += "--capture-preview=$CapturePreview" }
& $godotCommand.Source @previewArguments
exit $LASTEXITCODE
