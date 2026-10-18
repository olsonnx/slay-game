$projectPath = Split-Path -Parent $PSScriptRoot
$labPath = Join-Path $projectPath "artifacts/rebalance-implementation-2026-10-15"
$summary = @()
$allResults = @{}
foreach ($name in @("original", "recommended_30", "implemented_40")) {
    $r = Get-Content "$labPath/$name/results.json" -Raw | ConvertFrom-Json
    $allResults[$name] = $r
    $rounds = ($r.matches | Measure-Object rounds -Sum).Sum
    $bankSamples = ($r.matches | Measure-Object bank_samples -Sum).Sum
    $policies = @()
    foreach ($policy in @("save", "rush_knight", "invest_then_knight", "sustainable_knight")) {
        $rows = @($r.economy | Where-Object policy -eq $policy)
        $knightRows = @($rows | Where-Object first_knight -gt 0)
        $policies += [ordered]@{
            policy = $policy; first_knight = ($knightRows | Measure-Object first_knight -Average).Average
            gold = ($rows | Measure-Object gold -Average).Average
            income = ($rows | Measure-Object income -Average).Average
            wages = ($rows | Measure-Object wages -Average).Average
            deaths = ($rows | Measure-Object deaths -Sum).Sum
        }
    }
    $summary += [ordered]@{
        profile = $name; matches = $r.matches.Count
        completed = @($r.matches | Where-Object winner -ge 0).Count
        mean_rounds = $rounds / $r.matches.Count
        mean_knights = ($r.matches | Measure-Object knight_round_samples -Sum).Sum / $rounds
        mean_soldiers = ($r.matches | Measure-Object soldier_round_samples -Sum).Sum / $rounds
        mean_scouts = ($r.matches | Measure-Object scout_round_samples -Sum).Sum / $rounds
        mean_first_knight_round = ($r.matches | Where-Object first_knight_round -gt 0 | Measure-Object first_knight_round -Average).Average
        mean_settlement_deaths = ($r.matches | Measure-Object settlement_deaths -Sum).Sum / $r.matches.Count
        mean_captures = ($r.matches | Measure-Object captures -Sum).Sum / $r.matches.Count
        duels = ($r.matches | Measure-Object duels -Sum).Sum
        deficit_bank_percent = 100 * ($r.matches | Measure-Object deficit_bank_samples -Sum).Sum / $bankSamples
        checks = $r.checks; failures = $r.failures; economy = $policies
        unresolved = @($r.matches | Where-Object winner -lt 0)
    }
}
$paired = foreach ($r in $allResults["implemented_40"].matches) {
    $other = $allResults["recommended_30"].matches | Where-Object { $_.size -eq $r.size -and $_.seed -eq $r.seed }
    [ordered]@{ size=$r.size; seed=$r.seed; round_difference=$r.rounds - $other.rounds; first_knight_difference=$r.first_knight_round - $other.first_knight_round }
}
$result = [ordered]@{ profiles=$summary; price_effect_pairs=@($paired) }
$result | ConvertTo-Json -Depth 12 | Set-Content "$labPath/summary.json"
$result | ConvertTo-Json -Depth 12
