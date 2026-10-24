extends Control
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
const Progress = preload("res://src/settings/account_progress.gd")
var level_label: Label
var award_label: Label
var amount_label: Label
var bar: ProgressBar
var animation: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label = Ui.label_at(self, "", Vector2.ZERO, 16)
	award_label = Ui.label_at(self, "", Vector2.ZERO, 14, Ui.ACCENT)
	award_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	award_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 28
	bar.offset_bottom = 38
	bar.add_theme_stylebox_override("background", Ui.control_style(Color("283b3e"), Vector2.ZERO, 4))
	bar.add_theme_stylebox_override("fill", Ui.control_style(Ui.ACCENT, Vector2.ZERO, 4))
	add_child(bar)
	amount_label = Ui.label_at(self, "", Vector2(0, 43), 12, Ui.MUTED)
	set_total(0)

func set_total(total: float) -> void:
	var value := Progress.progress(roundi(total))
	level_label.text = Loc.text("Level %d") % value.level
	bar.max_value = value.needed
	bar.value = value.current
	amount_label.text = Loc.text("%d / %d XP") % [value.current, value.needed]

func show_profile(total: int) -> void:
	if animation != null: animation.kill()
	set_total(total)
	award_label.text = Loc.text("%d XP total") % total

func show_award(receipt: Dictionary, animate := true) -> void:
	if animation != null: animation.kill()
	var leveled_up: bool = Progress.progress(receipt.after).level > Progress.progress(receipt.before).level
	award_label.text = (Loc.text("+%d XP · Level up!") if leveled_up else Loc.text("+%d XP")) % receipt.earned
	set_total(receipt.before if animate else receipt.after)
	if animate:
		animation = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		animation.tween_interval(0.3)
		animation.tween_method(set_total, float(receipt.before), float(receipt.after), 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
