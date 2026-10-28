param(
    [string]$Godot = "godot",
    [string]$Template = "",
    [string]$Label = "closed-01"
)
$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
if ($Label -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,39}$') { throw "Use a short alphanumeric build label (hyphens allowed)." }
$engine = (Get-Command $Godot -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$project = Get-Content (Join-Path $projectPath "project.godot") -Raw
$version = [regex]::Match($project, '(?m)^config/version="([^"]+)"').Groups[1].Value
if (-not $version) { throw "Missing game version." }
$name = "Slay-and-Reign-$version-$Label-windows-x64"
$output = Join-Path $projectPath "builds/$name"
$archive = "$output.zip"
if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath $archive)) { throw "Build already exists. Choose a new -Label to keep each shared build identifiable." }
if ($Template) { $Template = (Resolve-Path -LiteralPath $Template).Path }
$presetPath = Join-Path $projectPath "export_presets.cfg"
$preset = [IO.File]::ReadAllBytes($presetPath)
$previousAppData = $env:APPDATA
New-Item -ItemType Directory -Path $output | Out-Null
# Never import or re-export previous packaged games as project resources.
Set-Content -LiteralPath (Join-Path $projectPath "builds/.gdignore") -Value ""
try {
    # Keep exports away from the developer's saved profile and preferences.
    $env:APPDATA = Join-Path $projectPath "artifacts/playtest-export-userdata"
    New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    if ($Template) {
        $settings = [Text.Encoding]::UTF8.GetString($preset)
        $settings = $settings.Replace('custom_template/release=""', 'custom_template/release="' + $Template.Replace('\', '/') + '"')
        [IO.File]::WriteAllText($presetPath, $settings, [Text.UTF8Encoding]::new($false))
    }
    $executable = Join-Path $output "Slay and Reign.exe"
    $exportLog = Join-Path $projectPath "artifacts/playtest-export-$Label.log"
    $result = & $engine --headless --path $projectPath --export-release "Windows Desktop" $executable 2>&1
    $exportCode = $LASTEXITCODE
    $result | Set-Content $exportLog
    if ($exportCode -ne 0 -or ($result -match 'SCRIPT ERROR:|^ERROR:')) { throw "Export failed. See $exportLog" }
    foreach ($required in @("Slay and Reign.exe", "Slay and Reign.pck", "steam_api64.dll", "libgodotsteam.windows.template_release.x86_64.dll")) {
        if (-not (Test-Path -LiteralPath (Join-Path $output $required))) { throw "Export is missing $required" }
    }
    Copy-Item -LiteralPath (Join-Path $projectPath "docs/playtest/START-HERE.txt") -Destination $output
    $licenses = Join-Path $output "licenses"
    New-Item -ItemType Directory -Path $licenses | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectPath "addons/godotsteam/license.md") -Destination (Join-Path $licenses "GodotSteam.txt")
    Copy-Item -LiteralPath (Join-Path $projectPath "resources/shaders/water.LICENSE.md") -Destination (Join-Path $licenses "Water-shader.txt")
    Copy-Item -Path (Join-Path $projectPath "docs/playtest/licenses/*.txt") -Destination $licenses
    @("Slay & Reign $version / $Label", "Packaged UTC: $([DateTime]::UtcNow.ToString('o'))", "Engine: $(& $engine --version)", "Source revision: $(git -C $projectPath rev-parse HEAD)", "Working tree modified: $([bool](git -C $projectPath status --porcelain))") | Set-Content (Join-Path $output "BUILD.txt")
    Compress-Archive -LiteralPath $output -DestinationPath $archive -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    "$hash  $name.zip" | Set-Content "$archive.sha256.txt"
    Write-Output "Created $archive"
} finally {
    [IO.File]::WriteAllBytes($presetPath, $preset)
    $env:APPDATA = $previousAppData
}
