$projectPath = Split-Path -Parent $PSScriptRoot
$labPath = Join-Path $projectPath "artifacts/rebalance-lab-2026-10-15"
$summary = @()
foreach ($folder in Get-ChildItem $labPath -Directory) {
    $r = Get-Content "$($folder.FullName)/results.json" -Raw | ConvertFrom-Json
    $s = Get-Content "$($folder.FullName)/supplement.json" -Raw | ConvertFrom-Json
    if (Test-Path "$($folder.FullName)/extended.json") {
        $e = Get-Content "$($folder.FullName)/extended.json" -Raw | ConvertFrom-Json
        $r.matches = @($r.matches) + @($e.matches)
    }
    $rounds = ($r.matches | Measure-Object rounds -Sum).Sum
    $bankSamples = ($r.matches | Measure-Object bank_samples -Sum).Sum
    $policies = @()
    foreach ($policy in @("save", "rush_knight", "invest_then_knight", "sustainable_knight")) {
        $rows = @($s.economy | Where-Object policy -eq $policy)
        $knightRows = @($rows | Where-Object first_knight -gt 0)
        $policies += [ordered]@{
            policy = $policy; runs = $rows.Count; knight_runs = $knightRows.Count
            first_knight = ($knightRows | Measure-Object first_knight -Average).Average
            gold = ($rows | Measure-Object gold -Average).Average
            income = ($rows | Measure-Object income -Average).Average
            wages = ($rows | Measure-Object wages -Average).Average
            deaths = ($rows | Measure-Object deaths -Sum).Sum
        }
    }
    $summary += [ordered]@{
        profile = $folder.Name
        matches = $r.matches.Count
        completed = @($r.matches | Where-Object winner -ge 0).Count
        mean_rounds_including_timeouts = $rounds / $r.matches.Count
        mean_knights_on_board = ($r.matches | Measure-Object knight_round_samples -Sum).Sum / $rounds
        deficit_bank_percent = 100 * ($r.matches | Measure-Object deficit_bank_samples -Sum).Sum / $bankSamples
        preparation_deaths = ($r.matches | Measure-Object starvation_deaths -Sum).Sum
        duels = ($r.matches | Measure-Object duels -Sum).Sum
        failures = $r.failures + $s.failures
        checks = $r.checks + $s.checks
        tactics = $s.tactics; two_knight_budget = $s.two_knight_budget; economy = $policies
        unresolved = @($r.matches | Where-Object winner -lt 0)
    }
}
$summary | ConvertTo-Json -Depth 12 | Set-Content "$labPath/summary.json"
$summary | ConvertTo-Json -Depth 12
