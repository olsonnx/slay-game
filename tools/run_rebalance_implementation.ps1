param([string]$Godot = "C:\Users\Olek1\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe")
$projectPath = Split-Path -Parent $PSScriptRoot
$labPath = Join-Path $projectPath "artifacts/rebalance-implementation-2026-10-15"
$originalSource = Join-Path $projectPath "artifacts/rebalance-lab-2026-10-15/baseline/src/game"
$profiles = @(
    @{ name = "original"; source = $originalSource },
    @{ name = "recommended_30"; source = "$projectPath/src/game" },
    @{ name = "implemented_40"; source = "$projectPath/src/game" }
)
$jobs = @()
foreach ($profile in $profiles) {
    $target = Join-Path $labPath $profile.name
    New-Item -ItemType Directory -Path "$target/src/game" -Force | Out-Null
    New-Item -ItemType Directory -Path "$target/src/localization" -Force | Out-Null
    Copy-Item "$projectPath/src/localization/text.gd" "$target/src/localization/" -Force
    Copy-Item "$($profile.source)/*.gd" "$target/src/game/" -Force
    Copy-Item "$PSScriptRoot/rebalance_lab.gd" "$target/probe.gd" -Force
    Set-Content "$target/project.godot" "config_version=5`n[application]`nconfig/name=`"RebalanceImplementationLab`"" -Encoding utf8
    if ($profile.name -eq "recommended_30") {
        $catalogPath = Join-Path $target "src/game/game_catalog.gd"
        $catalog = [IO.File]::ReadAllText($catalogPath).Replace("UNIT_PRICES := [0, 10, 20, 40]", "UNIT_PRICES := [0, 10, 20, 30]")
        [IO.File]::WriteAllText($catalogPath, $catalog)
    }
    # Count only deaths returned by real settlement; search copies have their own counter.
    $rulesPath = Join-Path $target "src/game/kingdom_rules.gd"
    $rules = [IO.File]::ReadAllText($rulesPath).Replace("var cells: Dictionary", "var lab_settlement_deaths := 0`nvar cells: Dictionary")
    $rules = $rules.Replace("`treturn deaths", "`tlab_settlement_deaths += deaths`n`treturn deaths")
    [IO.File]::WriteAllText($rulesPath, $rules)
    $profile | ConvertTo-Json | Set-Content "$target/profile.json"
    $jobs += Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", "`"$target`"", "--log-file", "`"$target/godot.log`"", "--script", "probe.gd", "--", "--seeds=8") -WindowStyle Hidden -RedirectStandardOutput "$target/stdout.log" -RedirectStandardError "$target/stderr.log" -PassThru
}
Write-Output "Comparing original, recommendation at 30 G, and implementation at 40 G on 16 maps each."
foreach ($job in $jobs) {
    $job.WaitForExit()
    if ($job.ExitCode -ne 0) { throw "Godot exited with $($job.ExitCode)" }
}
foreach ($profile in $profiles) {
    $target = Join-Path $labPath $profile.name
    $result = Get-Content "$target/results.json" -Raw | ConvertFrom-Json
    if ($result.failures -gt 0 -or @($result.matches).Count -ne 16) { throw "Invalid results: $($profile.name)" }
    if (Select-String -Path "$target/stderr.log" -Pattern "SCRIPT ERROR:|^ERROR:" -Quiet) { throw "Engine error: $($profile.name)" }
}
Get-Content "$labPath/*/stdout.log" -Tail 2
