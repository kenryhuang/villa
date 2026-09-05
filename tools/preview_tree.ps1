param(
    [string]$CapturePreview = "",
    [ValidateSet("front", "side", "back", "detail")]
    [string]$View = ""
)

$godotCommand = Get-Command godot_console.exe -ErrorAction SilentlyContinue
if ($null -eq $godotCommand) {
    $godotCommand = Get-Command godot.exe -ErrorAction Stop
}

$projectRoot = Split-Path -Parent $PSScriptRoot
& $godotCommand.Source --headless --editor --path $projectRoot --quit
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$previewArguments = @("--path", $projectRoot, "--resolution", "1440x1000", "res://scenes/preview/tree_3d_preview.tscn")
if ($CapturePreview -or $View) {
    $previewArguments += "--"
}
if ($CapturePreview) {
    $previewArguments += "--capture-preview=$CapturePreview"
}
if ($View) {
    $previewArguments += "--view=$View"
}
& $godotCommand.Source @previewArguments
$previewExitCode = $LASTEXITCODE
exit $previewExitCode
