$rootPath = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $rootPath 'artifacts/heavy_profile_source'
New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
$names = @('kingdom_rules', 'ai_analysis', 'ai_queries', 'ai_candidates', 'ai_planner', 'kingdom_movement')
foreach ($name in $names) {
    $source = Get-Content -LiteralPath (Join-Path $rootPath "src/game/$name.gd") -Raw
    foreach ($dependency in $names) {
        $source = $source.Replace("res://src/game/$dependency.gd", "res://artifacts/heavy_profile_source/$dependency.gd")
    }
    $wrappers = switch ($name) {
        'ai_analysis' { @(
            @('static func snapshot(model):', 'static func snapshot(model):', '_measured_snapshot(model)', 'snapshot'),
            @('static func evaluate(model, faction: int, queries = null) -> float:', 'static func evaluate(model, faction: int, queries = null) -> float:', '_measured_evaluate(model, faction, queries)', 'evaluate')
        ) }
        'ai_candidates' { @(
            @('static func movements(model, faction: int, queries = null) -> Array:', 'static func movements(model, faction: int, queries = null) -> Array:', '_measured_movements(model, faction, queries)', 'movement_candidates'),
            @('static func preparation(model, faction: int, queries = null) -> Array:', 'static func preparation(model, faction: int, queries = null) -> Array:', '_measured_preparation(model, faction, queries)', 'spending_candidates')
        ) }
        'kingdom_movement' { @(
            @('static func friendly_routes(state, source: Vector2i) -> Dictionary:', 'static func friendly_routes(state, source: Vector2i) -> Dictionary:', '_measured_friendly_routes(state, source)', 'routes'),
            @('static func reachable_targets(state, source: Vector2i) -> Dictionary:', 'static func reachable_targets(state, source: Vector2i) -> Dictionary:', '_measured_reachable_targets(state, source)', 'targets')
        ) }
        default { @() }
    }
    foreach ($wrapper in $wrappers) {
        $renamed = $wrapper[0].Replace('func ', 'func _measured_')
        $source = $source.Replace($wrapper[0], $renamed)
        $source += "`n" + $wrapper[1] + "`n`tvar started := Time.get_ticks_usec()`n`tvar result = " + $wrapper[2] + "`n`tpreload(`"res://artifacts/heavy_profile_source/meter.gd`").record(`"" + $wrapper[3] + "`", Time.get_ticks_usec() - started)`n`treturn result`n"
    }
    Set-Content -LiteralPath (Join-Path $profilePath "$name.gd") -Value $source -Encoding utf8
}
@'
extends RefCounted
static var counters: Dictionary = {}
static func record(label: String, usec: int) -> void:
    if not counters.has(label): counters[label] = {"calls": 0, "ms": 0.0}
    counters[label]["calls"] += 1
    counters[label]["ms"] += usec / 1000.0
'@ | Set-Content -LiteralPath (Join-Path $profilePath 'meter.gd') -Encoding utf8
