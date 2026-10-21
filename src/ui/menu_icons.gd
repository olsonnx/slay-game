extends RefCounted
const Ui = preload("res://src/ui/ui_theme.gd")

static func editor() -> Texture2D:
	return Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 4H4v16h16v-9 M4 15l5-5 5 5 M13 11l-1 4 4-1 6-6-3-3z M17 7l3 3"/></g></svg>')

static func replays() -> Texture2D:
	return Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9a8.5 8.5 0 1 1 0 7 M4 3v6h6"/></g><path d="m10 8 6 4-6 4z" fill="#ede7d4"/></svg>')

static func options() -> Texture2D:
	return preload("res://assets/ui/cog.svg")

static func quit() -> Texture2D:
	return Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linecap="round"><path d="M12 3v9 M6.4 5.8a8.5 8.5 0 1 0 11.2 0"/></g></svg>')
