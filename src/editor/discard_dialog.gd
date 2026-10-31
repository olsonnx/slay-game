extends "res://src/ui/confirmation_panel.gd"
## Editor wording over the same confirmation used by gameplay settings.
func _init() -> void:
	title = "Unsaved level"
	dialog_text = "Discard changes to this level?"
	cancel_text = "Keep editing"
	confirm_text = "Discard changes"
	primary_confirm = false
