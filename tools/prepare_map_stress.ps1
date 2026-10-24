$destination = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/map_stress_source'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$rootPath = Split-Path -Parent $PSScriptRoot
$sizes = Get-Content (Join-Path $rootPath 'src/game/map_sizes.gd') -Raw
$sizes = $sizes.Replace('static func spec(size_id: String) -> Dictionary:', "static var stress_profile: Dictionary = {}`n`nstatic func spec(size_id: String) -> Dictionary:`n`tif size_id == `"stress`":`n`t`treturn stress_profile")
Set-Content -LiteralPath (Join-Path $destination 'map_sizes.gd') -Value $sizes -Encoding utf8
$generator = Get-Content (Join-Path $rootPath 'src/game/map_generator.gd') -Raw
$generator = $generator.Replace('res://src/game/map_sizes.gd', 'res://artifacts/map_stress_source/map_sizes.gd')
$generator = $generator.Replace('size_id if MapSizes.SPECS.has(size_id) else "small"', 'size_id if size_id == "stress" or MapSizes.SPECS.has(size_id) else "small"')
$generator = $generator.Replace('for q in range(-20, 21):', 'for q in range(-ceili(bounds.x / sqrt(3.0) + bounds.y / 3.0), ceili(bounds.x / sqrt(3.0) + bounds.y / 3.0) + 1):')
$generator = $generator.Replace('for r in range(-12, 13):', 'for r in range(-ceili(bounds.y / 1.5), ceili(bounds.y / 1.5) + 1):')
$generator = $generator.Replace('var state', "var state`nvar phase_started: int`n`nfunc checkpoint(label: String) -> void:`n`tvar now := Time.get_ticks_usec()`n`tstate.generation_stages[label] = (now - phase_started) / 1000.0`n`tphase_started = now")
$generator = $generator.Replace('state.map_size = size_id', "phase_started = Time.get_ticks_usec()`n`tstate.generation_stages.clear()`n`tstate.map_size = size_id")
foreach ($entry in @(
    @('var seeds := starting_sites().slice(0, mainland_factions)', "var seeds := starting_sites().slice(0, mainland_factions)`n`tcheckpoint(`"starting_sites`")"),
    @('# Remove any detached coastal specks', "checkpoint(`"links_and_lobes`")`n`t# Remove any detached coastal specks"),
    @('# Guarantee expansion space', "checkpoint(`"connectivity_cleanup`")`n`t# Guarantee expansion space"),
    @('# Cut bays and interior lakes', "checkpoint(`"minimum_land_fill`")`n`t# Cut bays and interior lakes"),
    @('# All factions start', "checkpoint(`"erosion`")`n`t# All factions start"),
    @('state.rebuild_kingdoms()', "checkpoint(`"ownership_and_trees`")`n`tstate.rebuild_kingdoms()`n`tcheckpoint(`"kingdoms`")"),
    @('generate_province_resources()', "generate_province_resources()`n`tcheckpoint(`"resources`")"),
    @('generate_mountains()', "generate_mountains()`n`tcheckpoint(`"mountains`")")
)) {
    # Only instrument calls, not matching function declarations.
    $generator = $generator.Replace("`t" + $entry[0], "`t" + $entry[1])
}
Set-Content -LiteralPath (Join-Path $destination 'map_generator.gd') -Value $generator -Encoding utf8
$rules = Get-Content (Join-Path $rootPath 'src/game/kingdom_rules.gd') -Raw
$rules = $rules.Replace('res://src/game/map_generator.gd', 'res://artifacts/map_stress_source/map_generator.gd').Replace('res://src/game/map_sizes.gd', 'res://artifacts/map_stress_source/map_sizes.gd')
$rules = $rules.Replace('var cells:', "var generation_stages: Dictionary = {}`nvar cells:")
Set-Content -LiteralPath (Join-Path $destination 'kingdom_rules.gd') -Value $rules -Encoding utf8
$optimizedGenerator = $generator.Replace('if not connected_land():', 'if not erosion_neighbors_connected(coord):')
$optimizedGenerator = $optimizedGenerator.Replace('if not passable_land_connected():', 'if not mountain_neighbors_connected(coord):')
$optimizedGenerator += @'

# Exact deletion test: a connected graph stays connected iff all surviving
# neighbours of the removed vertex are connected to each other.
func erosion_neighbors_connected(removed: Vector2i) -> bool:
	var neighbors: Array[Vector2i] = state.neighbors(removed)
	return remaining_neighbors_connected(neighbors)

func mountain_neighbors_connected(removed: Vector2i) -> bool:
	var neighbors: Array[Vector2i] = []
	for coord in state.neighbors(removed):
		if not state.is_mountain(coord):
			neighbors.append(coord)
	return remaining_neighbors_connected(neighbors, true)

func remaining_neighbors_connected(neighbors: Array[Vector2i], passable_only := false) -> bool:
	if neighbors.size() <= 1:
		return true
	var wanted: Dictionary = {}
	for coord in neighbors:
		wanted[coord] = true
	var first: Vector2i = neighbors[0]
	var visited := {first: true}
	var pending := [first]
	wanted.erase(first)
	var index := 0
	while index < pending.size():
		var current: Vector2i = pending[index]
		index += 1
		for next in state.neighbors(current):
			if passable_only and state.is_mountain(next):
				continue
			if not visited.has(next):
				visited[next] = true
				pending.append(next)
				wanted.erase(next)
				if wanted.is_empty():
					return true
	return false
'@
Set-Content -LiteralPath (Join-Path $destination 'map_generator_optimized.gd') -Value $optimizedGenerator -Encoding utf8
$optimizedRules = $rules.Replace('res://artifacts/map_stress_source/map_generator.gd', 'res://artifacts/map_stress_source/map_generator_optimized.gd')
Set-Content -LiteralPath (Join-Path $destination 'kingdom_rules_optimized.gd') -Value $optimizedRules -Encoding utf8
Get-FileHash -Path (Join-Path $rootPath 'src/game/map_generator.gd'), (Join-Path $rootPath 'src/game/map_sizes.gd'), (Join-Path $rootPath 'src/rendering/static_batches.gd') | Select-Object Path,Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'source_hashes.json') -Encoding utf8
