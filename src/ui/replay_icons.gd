extends RefCounted
const Ui = preload("res://src/ui/ui_theme.gd")
static var cache: Dictionary = {}

static func get_icon(kind: String, primary := false) -> Texture2D:
	if kind == "camera": return preload("res://assets/ui/view_3d.svg")
	var key := kind + str(primary)
	if cache.has(key): return cache[key]
	var shape := ""
	match kind:
		"play": shape = '<path d="m8 5 11 7-11 7z" fill="currentColor" stroke="none"/>'
		"pause": shape = '<path d="M8 5v14 M16 5v14" stroke-width="3.5"/>'
		"start": shape = '<path d="M4 5v14"/><path d="m12 6-6 6 6 6zm8 0-6 6 6 6z" fill="currentColor" stroke="none"/>'
		"previous": shape = '<path d="M6 5v14"/><path d="m18 6-9 6 9 6z" fill="currentColor" stroke="none"/>'
		"next": shape = '<path d="M18 5v14"/><path d="m6 6 9 6-9 6z" fill="currentColor" stroke="none"/>'
		"end": shape = '<path d="M20 5v14"/><path d="m4 6 6 6-6 6zm8 0 6 6-6 6z" fill="currentColor" stroke="none"/>'
		"back": shape = '<path d="M20 12H4m6-6-6 6 6 6"/>'
		"recording": shape = '<path d="M3 7V5h7l3 3h8v3 M3 20V9h7l2 2h10l-3 9z"/>'
		"hide", "show":
			shape = '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'
			if kind == "hide": shape += '<path d="m3 3 18 18"/>'
	var color := "#20332d" if primary else "#ede7d4"
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [color, shape.replace("currentColor", color)]
	cache[key] = Ui.svg_texture(svg)
	return cache[key]
