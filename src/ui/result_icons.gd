extends RefCounted
const Ui = preload("res://src/ui/ui_theme.gd")

static func restart() -> Texture2D:
	return Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 26 26"><g fill="none" stroke="#263b3d" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 10a9 9 0 1 1 0 7 M5 4v6h6"/></g></svg>')

static func save() -> Texture2D:
	return Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 26 26"><g fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linejoin="round"><path d="M4 3h15l4 4v16H3V3z M8 3v7h10V3 M7 23V15h12v8 M15 4v4"/></g></svg>')

static func results() -> Texture2D:
	return Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 7V3h12v18H9v-4 M13 7h4 M13 11h4 M13 15h4 M11 12H2l3-3 M2 12l3 3"/></g></svg>')
