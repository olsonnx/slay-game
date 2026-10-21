param([string]$Godot = "godot", [string]$From = "", [string]$Python = "python")

$projectPath = Split-Path -Parent $PSScriptRoot
$pythonExecutable = (Get-Command $Python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$suites = @("test_ai", "test_game", "test_animation", "test_input", "test_audio", "test_review", "test_menus", "test_economy_ui", "test_turn_feedback", "test_modern", "test_presentation", "test_expansion", "test_resources_terrain", "test_map_sizes", "test_events_spells", "test_performance", "test_menu_background", "test_startup", "test_ui_layout", "test_playback_speed", "test_keys", "test_heatmap")
$suites += "test_indicators"
$suites += "test_static_batches"
$suites += "test_menu_rendering"
$suites += "test_level_editor"
$suites += "test_scaling"
$suites += "test_army_optimization"
$suites += "test_terrain_templates"
$suites += "test_capture_updates"
$suites += "test_strategic_ai"
$suites += "test_hotseat"
$suites += "test_multiplayer_setup"
$suites += "test_multiplayer_maps"
$suites += "test_ui_consistency"
$suites += "test_tutorial"
$suites += "test_tutorial_editor"
$suites += "test_rebalance"
$suites += "test_localization"
$suites += "test_capital_replacement"
$suites += "test_ai_housing"
$suites += "test_ai_tactics"
$suites += "test_ai_followup"
$suites += "test_huge_warning"
$suites += "test_replay"
$suites += "test_results"
$suites += "test_world_generation"
$suites += "test_points_of_interest"
$suites += "test_ai_bridge_campaign"
$suites += "test_entrench"
$suites += "test_architecture"
$suites += "test_simulation_worker"
$suites += "test_unit_sprites"
$suites += "test_unit_readiness"
$suites += "test_new_events"
$suites += "test_kingdom_palettes"
$suites += "test_replay_viewer"
$suites += "test_camera_zoom"
$suites += "test_birds"
$suites += "test_bird_heads"
$suites += "test_editor_outcomes"
$suites += "test_editor_loading"
$suites += "test_editor_interaction"
$suites += "test_editor_water_hover"
$suites += "test_transition_batches"
$suites += "test_wildlife"
$suites += "test_wildlife_presentation"
$suites += "test_wildlife_alerts"
$suites += "test_wildlife_inspection"
$suites += "test_editor_lairs"
$suites += "test_lighting"
$suites += "test_lighting_transition"
$suites += "test_sprite_lighting"
$suites += "test_ledger"
if ($From -ne "") {
    $firstSuite = [Array]::IndexOf($suites, $From)
    if ($firstSuite -lt 0) { throw "Unknown suite: $From" }
    $suites = $suites[$firstSuite..($suites.Count - 1)]
}
$previousAppData = $env:APPDATA
$testAppData = Join-Path $projectPath "artifacts/test-userdata"
New-Item -ItemType Directory -Path $testAppData -Force | Out-Null
$env:APPDATA = $testAppData
try {
foreach ($suite in $suites) {
    # Bound failed scripts too: Godot can stay alive after a runtime error.
    $result = & $Godot --headless --path $projectPath --log-file "$projectPath/artifacts/$suite.log" --script "tests/$suite.gd" --quit-after 18000 2>&1
    $exitStatus = $LASTEXITCODE
    $result | Write-Output
    if ($exitStatus -ne 0 -or ($result -match "SCRIPT ERROR:|^ERROR:") -or -not ($result -match "checks: \d+ passed, 0 failed")) {
        throw "Test suite failed: $suite"
    }
}
Write-Output "All $($suites.Count) test suites passed."
& $pythonExecutable -B -m unittest discover -s (Join-Path $projectPath "tests") -p test_replay_report.py
if ($LASTEXITCODE -ne 0) { throw "Python replay reader tests failed" }
} finally {
    $env:APPDATA = $previousAppData
}
