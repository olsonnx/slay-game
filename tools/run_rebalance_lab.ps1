param([string]$Godot = "C:\Users\Olek1\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe", [switch]$Supplement, [switch]$Extended)
$projectPath = Split-Path -Parent $PSScriptRoot
$labPath = Join-Path $projectPath "artifacts/rebalance-lab-2026-10-15"
# Preserve the research run's pre-implementation rules when reproducing it later.
$sourcePath = Join-Path $labPath "baseline/src/game"
if (-not (Test-Path $sourcePath)) { $sourcePath = Join-Path $projectPath "src/game" }
$profiles = @(
    @{ name = "baseline"; wages = "2, 5, 12"; cap = $false; cost = 10 },
    @{ name = "cap_only"; wages = "2, 5, 12"; cap = $true; cost = 10 },
    @{ name = "cap_16"; wages = "2, 6, 16"; cap = $true; cost = 10 },
    @{ name = "cap_18"; wages = "2, 6, 18"; cap = $true; cost = 10 },
    @{ name = "cap_24"; wages = "2, 8, 24"; cap = $true; cost = 10 },
    @{ name = "cap_price15"; wages = "2, 5, 12"; cap = $true; cost = 15 }
)
if ($Extended) { $profiles = @($profiles | Where-Object { $_.name -in @("cap_16", "cap_18") }) }
$jobs = @()
foreach ($profile in $profiles) {
    $target = Join-Path $labPath $profile.name
    New-Item -ItemType Directory -Path "$target/src/game" -Force | Out-Null
    if ([IO.Path]::GetFullPath($sourcePath) -ne [IO.Path]::GetFullPath("$target/src/game")) {
        Copy-Item "$sourcePath/*.gd" "$target/src/game/" -Force
    }
    Copy-Item "$PSScriptRoot/rebalance_lab.gd" "$target/probe.gd" -Force
    Set-Content "$target/project.godot" "config_version=5`n[application]`nconfig/name=`"RebalanceLab`"" -Encoding utf8
    $catalogPath = Join-Path $target "src/game/game_catalog.gd"
    $catalog = [IO.File]::ReadAllText($catalogPath)
    $catalog = $catalog.Replace("MODERN_UPKEEP := [0, 2, 5, 12]", "MODERN_UPKEEP := [0, $($profile.wages)]")
    $catalog = $catalog.Replace("UNIT_COST := 10", "UNIT_COST := $($profile.cost)")
    [IO.File]::WriteAllText($catalogPath, $catalog)
    if ($profile.cap) {
        $movementPath = Join-Path $target "src/game/kingdom_movement.gd"
        $movement = [IO.File]::ReadAllText($movementPath)
        $movement = $movement.Replace("maxi(strength, local_defense(state, next))", "maxi(strength, mini(2, local_defense(state, next)))")
        [IO.File]::WriteAllText($movementPath, $movement)
    }
    $profile | ConvertTo-Json | Set-Content "$target/profile.json"
    $arguments = @("--headless", "--path", "`"$target`"", "--log-file", "`"$target/godot.log`"", "--script", "probe.gd")
    $logPrefix = ""
    if ($Supplement) { $arguments += @("--", "--supplement"); $logPrefix = "supplement-" }
    if ($Extended) { $arguments += @("--", "--extended"); $logPrefix = "extended-" }
    $jobs += Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput "$target/$($logPrefix)stdout.log" -RedirectStandardError "$target/$($logPrefix)stderr.log" -PassThru
}
$jobs | Select-Object Id, ProcessName
Write-Output "Isolated labs: $labPath"
foreach ($job in $jobs) {
    $job.WaitForExit()
    if ($job.ExitCode -ne 0) { throw "Godot process $($job.Id) exited with $($job.ExitCode)" }
}
Get-Content "$labPath/*/$($logPrefix)stdout.log" -Tail 2
foreach ($profile in $profiles) {
    $target = Join-Path $labPath $profile.name
    $resultFile = Join-Path $target $(if ($Extended) { "extended.json" } elseif ($Supplement) { "supplement.json" } else { "results.json" })
    if (-not (Test-Path $resultFile)) { throw "Missing results: $resultFile" }
    $result = Get-Content $resultFile -Raw | ConvertFrom-Json
    if (-not $Supplement -and @($result.matches).Count -ne 8) { throw "Expected eight matches: $($profile.name)" }
    if ($result.failures -gt 0) { throw "Failed checks: $($profile.name)" }
    if (Select-String -Path "$target/$($logPrefix)stderr.log" -Pattern "SCRIPT ERROR:|^ERROR:" -Quiet) { throw "Engine error: $($profile.name)" }
}
