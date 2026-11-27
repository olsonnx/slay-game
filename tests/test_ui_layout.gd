extends SceneTree
const Ui = preload("res://src/ui/ui_theme.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func contained(box: Control, label: Control) -> bool:
	return Rect2(Vector2.ZERO, box.size).encloses(Rect2(label.position, label.size))

func capture(name_value: String) -> void:
	if not "--preview" in OS.get_cmdline_user_args():
		return
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/ui_%s.png" % name_value)

func formatting_checks() -> void:
	var formatter = preload("res://src/ui/event_text.gd")
	var mixed: String = formatter.rich_text("50%: gain 4 gold. 50%: this unit dies. Gain 1 mana.")
	expect(mixed.contains("[color=#a5d6a0]4 gold[/color]") and mixed.contains("[color=#ed9b91]50%[/color]"), "Mixed chances keep gains and losses separate")
	expect(mixed.contains("[color=#8fbfe8]1 mana[/color]") and not mixed.contains("[b]"), "Mana stays blue and unit mentions use regular text")
	var trade: String = formatter.rich_text("Pay 10 gold; permanently gain 1 gold per turn.")
	expect(trade.contains("[color=#ed9b91]10 gold[/color]") and trade.contains("[color=#a5d6a0]1 gold[/color]"), "Costs and permanent gains are scoped to their clauses")
	var wages: String = formatter.rich_text("Permanently reduce upkeep by 2 gold per Knight.")
	expect(wages.contains("[color=#a5d6a0]2 gold[/color]") and not wages.contains("[b]"), "Wage reductions retain benefit colours without bolding Knights")
	expect(formatter.rich_text("Pay 10 G. Cost 20 G. 0 gold.").contains("[color=#b5c6bd]0 gold[/color]"), "Zero resources retain the muted palette")
	expect(formatter.rich_text("Gain 0–2 gold.").contains("[color=#a5d6a0]0–2 gold[/color]"), "Ranges starting at zero still represent a gain")
	var units: String = formatter.rich_text("Scout Scouts Soldier Soldiers Knight Knights unit units army armies garrison garrisons scouted knighthood")
	expect(not units.contains("[b]") and units.contains("Scout Scouts Soldier Soldiers Knight Knights unit units army armies garrison garrisons scouted knighthood"), "Unit names, plurals and related words all retain regular typography")
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	root.add_child(label)
	var catalog = preload("res://src/game/event_catalog.gd")
	for id in catalog.EVENTS:
		var entry: Dictionary = catalog.EVENTS[id]
		var samples: Array = [entry["title"], entry["text"], entry.get("requirements", "")]
		for choice in entry["choices"]: samples.append_array(choice)
		for sample in samples:
			label.text = formatter.rich_text(sample)
			expect(label.get_parsed_text() == sample, "Universal formatting preserves catalog wording: " + id)
	for sample in ["[color=red]Scouts[/color] & Knights", "50%: dies. gain 4 gold; lose 1 mana.", "Gain 1–2 gold; 2 G lower Knight wages."]:
		label.text = formatter.rich_text(sample)
		expect(label.get_parsed_text() == sample, "Literal brackets, punctuation, ranges and words are preserved")
	label.free()
	var legacy_tip := preload("res://src/ui/compact_tooltip.gd").create("Pay 10 gold; permanently gain 1 gold per turn.", true)
	root.add_child(legacy_tip)
	var legacy_text: String = legacy_tip.get_child(0).get_parsed_text()
	expect(not legacy_text.contains(";") and legacy_text.contains("gold\n"), "Older semicolon-separated effects render on separate lines")
	legacy_tip.free()
	var button := preload("res://src/ui/tooltip_button.gd").new()
	root.add_child(button)
	button.text = "Recruit a Knight"
	button.size = Vector2(424, 38)
	var disabled_color := button.get_theme_color("font_disabled_color")
	formatter.decorate_choice(button)
	var caption: RichTextLabel = button.get_child(0)
	expect(button.text == "Recruit a Knight" and caption.get_parsed_text() == button.text and not caption.text.contains("[b]"), "Rich captions keep unit mentions regular while preserving native button text")
	expect(caption.mouse_filter == Control.MOUSE_FILTER_IGNORE and contained(button, caption), "Rich captions fit the button without intercepting clicks")
	button.disabled = true
	button.draw.emit()
	expect(caption.get_theme_color("default_color") == disabled_color, "Disabled choices retain their disabled caption colour")
	button.free()

func run() -> void:
	formatting_checks()
	var sound = root.get_node("Sound")
	var original_muted: bool = sound.is_muted()
	sound.set_muted(true, false)
	root.size = Vector2i(960, 620)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for modern in [true]:
		game.configure_rules_ui(modern)
		var first: Button = game.recruit_button
		var last: Button = game.spell_button if modern else game.build_button
		var right_padding: float = game.economy_dock.size.x - last.position.x - last.size.x
		expect(is_equal_approx(first.position.x, right_padding), "Dock action row has equal side padding in both rulesets")
		var resources: Control = game.hud.ore_control if modern else game.gold_control
		expect(is_equal_approx(game.gold_control.position.x, game.economy_dock.size.x - resources.position.x - resources.size.x), "Resource hit areas have equal outer side padding")
	game.configure_rules_ui(true)
	for kind in ["recruit", "build", "spells"]:
		game.open_shop(kind)
		game.shop_panel.reveal = 1
		var close_button: Button = game.shop_panel.get_node("Close")
		expect(close_button.size == Vector2(32, 32), "Shop close button remains square after theme sizing")
		expect(is_equal_approx(close_button.position.y, game.shop_panel.size.x - close_button.position.x - close_button.size.x), "Shop close button has equal top and right inset")
		expect(is_equal_approx(game.shop_items.position.y - close_button.position.y - close_button.size.y, 15), "Shop close button has 15 px clearance above the cards")
		var last_card: Button = game.shop_items.get_child(game.shop_items.get_child_count() - 1)
		expect(is_equal_approx(game.shop_items.position.x, game.shop_panel.size.x - game.shop_items.position.x - last_card.position.x - last_card.size.x), "Shop cards have equal left and right padding")
		expect(is_equal_approx(game.shop_panel.size.y - game.shop_items.position.y - game.shop_items.size.y, 15), "Shop cards have matching bottom padding")
		await capture(kind)
		close_button.pressed.emit()
		expect(not game.shop_panel.visible, "Square close button still cancels placement")
	for box in [game.province_view, game.stats_panel]:
		var close_button: Button = box.get_node("Close")
		expect(close_button.size == Vector2(32, 32), "Other close buttons share the square style")
	game.rules.rule_mode = "modern"
	game.configure_rules_ui(true)
	for node in game.help_panel.get_children():
		if node is Label:
			expect(contained(game.help_panel, node), "Help text fits inside the panel: %s (%s + %s in %s)" % [node.text, node.position, node.size, game.help_panel.size])
	game.help_panel.show()
	expect(root.get_visible_rect().encloses(game.help_panel.get_global_rect()), "Help fits the minimum window")
	await capture("help")
	game.help_panel.hide()
	var heights := {}
	for kind in ["mountain", "neutral"]:
		for coord in game.cells:
			if (kind == "mountain" and game.rules.is_mountain(coord)) or (kind == "neutral" and game.cells[coord]["owner"] < 0 and not game.rules.is_mountain(coord)):
				game.hovered = coord
				break
		game.show_world_tip()
		heights[kind] = game.world_tip.size.y
		expect(contained(game.world_tip, game.tip_label), "Wrapped %s tooltip fits immediately" % kind)
		expect(is_equal_approx(game.world_tip.size.y - game.tip_label.position.y - game.tip_label.size.y, 9), "Tooltip bottom padding is 9 px")
		await process_frame
		expect(contained(game.world_tip, game.tip_label), "Tooltip still fits after deferred text layout")
		# The first rendered frame can resolve the inherited fallback font.
		game.show_world_tip()
		var plain_text: String = game.tip_label.get_parsed_text()
		expect(not game.Tooltip.fit(game.world_tip, game.tip_label, plain_text), "Unchanged tooltip reuses layout")
		var screen := root.get_visible_rect().size
		for point in [Vector2(-20, -20), screen, Vector2(screen.x, 0), Vector2(0, screen.y)]:
			Ui.keep_on_screen(game.world_tip, point, screen)
			expect(root.get_visible_rect().encloses(game.world_tip.get_global_rect()), "Tooltip remains on screen at every corner")
		game.world_tip.position = Vector2(450, 200)
		await capture(kind)
	expect(heights["mountain"] <= heights["neutral"], "Mountain tooltip stays compact without irrelevant economy values")
	game.announce("A long notification with enough detail to wrap into several lines. ".repeat(6))
	expect(contained(game.toast_panel, game.notice_label), "Long notification fits banner")
	var long_height: float = game.toast_panel.size.y
	game.announce("Your turn.")
	expect(game.toast_panel.size.y < long_height, "Notification shrinks again for short text")
	game.announce(" \n\t")
	expect(not game.toast_panel.visible, "Blank announcements hide their panel immediately")
	game.game_over = true
	game._process(0.0)
	expect(not game.toast_panel.visible, "Completing a game without a message keeps the banner hidden")
	game.announce("Victory!")
	game._process(5.0)
	expect(game.toast_panel.visible, "A real result message remains visible after its timer expires")
	game.game_over = false
	game._process(0.0)
	expect(not game.toast_panel.visible, "Ordinary notifications hide after their timer expires")
	game.toast_panel.hide()
	var capital: Vector2i = game.active_capital()
	var original: Dictionary = game.cells[capital].duplicate(true)
	game.cells[capital]["fortified"] = true
	game.cells[capital]["barrier_used"] = true
	game.cells[capital]["event"] = "encounter"
	game.hovered = capital
	game.show_world_tip()
	expect(contained(game.world_tip, game.tip_label), "Stacked province statuses fit tooltip")
	game.cells[capital] = original
	# Real UI tooltip callbacks use the same compact renderer as world hovers.
	var tip_samples: Array[String] = [game.gold_control.tooltip_text, game.mana_control.tooltip_text]
	for kind in ["recruit", "build", "spells"]:
		game.open_shop(kind)
		for card in game.shop_items.get_children():
			var tooltip: Control = card._make_custom_tooltip(card.tooltip_text)
			game.ui_root.add_child(tooltip)
			expect(tooltip.size.x <= 304 and tooltip.size.y < 210, "Card tooltip is bounded and condensed")
			expect(not tooltip is Panel and not tooltip is PanelContainer, "Native tooltip content adds no nested background box")
			expect(contained(tooltip, tooltip.get_child(0)), "Card tooltip contains its coloured text")
			tip_samples.append(card.tooltip_text)
			tooltip.free()
	game.cancel_action()
	for sample in tip_samples:
		var tooltip: Control = game.Tooltip.create(sample)
		game.ui_root.add_child(tooltip)
		var rich: RichTextLabel = tooltip.get_child(0)
		expect(rich.get_parsed_text() == sample, "Rich colours preserve every tooltip value and restriction")
		await process_frame
		expect(contained(tooltip, rich), "Tooltip remains contained after actual font layout")
		tooltip.free()
	var rich: String = game.Tooltip.rich_text("Net +5 G · upkeep −2 G\nMana 1 / 3 · +2 mana\nCost 20 G")
	expect(rich.contains("[color=#a5d6a0]+5 G[/color]") and rich.contains("[color=#ed9b91]−2 G[/color]"), "Positive income is green and upkeep is red")
	expect(rich.contains("[color=#8fbfe8]1 / 3[/color]") and rich.contains("[color=#8fbfe8]+2 mana[/color]"), "Mana storage and gains are blue")
	expect(rich.contains("[color=#e5ca8b]20 G[/color]"), "Purchase costs use gold rather than income colours")
	game.Tooltip.fit(game.world_tip, game.tip_label, "A longer tooltip line that wraps across the maximum width. ".repeat(4))
	var large_size: Vector2 = game.world_tip.size
	game.Tooltip.fit(game.world_tip, game.tip_label, "Mountain\nImpassable")
	expect(game.world_tip.size.x < large_size.x and game.world_tip.size.y < large_size.y, "Tooltip shrinks in both dimensions after lengthy content")
	for coord in [capital, game.hovered]:
		game.hovered = coord
		game.presenter.invalidate_tip()
		game.show_world_tip()
		expect(not game.tip_label.get_parsed_text().to_lower().contains("defence"), "World tooltips omit defence numbers")
	for fortified in [false, true]:
		game.cells[capital]["fortified"] = fortified
		game.province_view.refresh(game.rules, capital, true)
		expect(contained(game.province_view, game.province_view.mana_label), "Province modifier fits panel")
		expect(game.province_view.mana_label.position.y + game.province_view.mana_label.size.y + 10 <= game.province_view.develop_button.position.y, "Province modifier stays above action button")
		expect(game.province_view.offset_bottom <= game.economy_dock.offset_top - 2, "Growing inspector stays above resource dock even during its entrance")
	game.inspect_province(capital)
	game.province_view.reveal = 1
	game.world_tip.hide()
	await capture("province")
	for id in game.rules.Events.EVENTS:
		var definition: Dictionary = game.rules.Events.EVENTS[id]
		game.event_dialog.present(definition, func(_index): pass)
		await process_frame
		expect(game.event_panel.get_node("EventTitle").get_parsed_text() == definition["title"] and game.event_panel.get_node("EventStory").get_parsed_text() == definition["text"], "Event title and story remain verbatim: " + id)
		for choice_index in range(definition["choices"].size()):
			var choice: Button = game.event_panel.get_children().filter(func(child): return child is Button)[choice_index]
			var original_choice: Array = definition["choices"][choice_index]
			var tooltip: Control = choice._make_custom_tooltip(choice.tooltip_text)
			game.ui_root.add_child(tooltip)
			var outcome: RichTextLabel = tooltip.get_child(0)
			expect(choice.text == original_choice[0] and choice.tooltip_text == original_choice[1] and outcome.get_parsed_text().replace("\n", " ") == original_choice[1].replace("\n", " "), "Event choice and all outcome wording remain verbatim: " + id)
			await process_frame
			expect(contained(tooltip, outcome), "Event outcome colours and sentence groups fit the tooltip: " + id)
			var ink_width := 0.0
			for line_index in range(outcome.get_line_count()): ink_width = maxf(ink_width, outcome.get_line_width(line_index))
			expect(outcome.size.x - ink_width <= 3.0, "Event tooltip has no excess space to the right: %s (box %.1f, ink %.1f)" % [id, outcome.size.x, ink_width])
			expect(not outcome.get_parsed_text().contains(";"), "Event effects use line breaks rather than semicolons: " + id)
			tooltip.free()
		var painting := game.event_panel.get_node_or_null("EventPainting") as TextureRect
		expect(painting != null, "Every encounter has dedicated or fallback art: " + id)
		if painting != null:
			var artwork: Dictionary = definition if definition.get("painting", "") != "" else game.rules.Events.DEFAULT_PAINTING
			expect(painting.texture.resource_path == game.rules.Events.event_texture_path(artwork), "Prepared event art takes precedence over the full-size source: " + id)
			expect(painting.mouse_filter != Control.MOUSE_FILTER_IGNORE and painting.tooltip_text.contains(artwork["painting_title"]) and painting.tooltip_text.contains(artwork["painting_artist"]), "Painting tooltip includes title and artist: " + id)
			expect(painting.texture != null and painting.material is ShaderMaterial and painting.material.get_shader_parameter("corner_radius") == 8.0, "Event paintings share the rounded sepia treatment: " + id)
			expect(is_equal_approx(painting.size.x / painting.size.y, 2.0), "Painting uses the consistent 2:1 event frame: " + id)
			expect(painting.position.y + painting.size.y < game.event_panel.get_node("EventStory").position.y, "Painting stays above event text: " + id)
		var event_title: RichTextLabel = game.event_panel.get_node("EventTitle")
		var event_story: RichTextLabel = game.event_panel.get_node("EventStory")
		var first_choice: Button = game.event_panel.get_node("EventChoice0")
		expect(event_title.position.y == 20 and event_title.position.y + event_title.size.y <= event_story.position.y and event_story.position.y + event_story.size.y < first_choice.position.y, "Title, story and choices fit without a category header or subtext: " + id)
		expect(game.event_panel.get_children().filter(func(child): return child is RichTextLabel).size() == 2, "Events show no requirements or hover instructions: " + id)
		var last_choice: Button = game.event_panel.get_child(game.event_panel.get_child_count() - 1)
		expect(is_equal_approx(game.event_panel.panel_height - last_choice.position.y - last_choice.size.y, 20), "Encounter retains consistent bottom padding: " + id)
		expect(root.get_visible_rect().encloses(game.event_panel.get_global_rect()), "Encounter fits minimum window: " + id)
	game.event_dialog.present({"title": "An unusually long encounter title that needs more than one line", "text": "A longer story still needs enough space above the choice buttons. ".repeat(4), "choices": [["Continue", "Continue exploring."]]}, func(_index): pass)
	await process_frame
	var title: RichTextLabel = game.event_panel.get_node("EventTitle")
	var story: RichTextLabel = game.event_panel.get_node("EventStory")
	var first_choice: Button = game.event_panel.get_node("EventChoice0")
	expect(title.position.y + title.size.y < story.position.y and story.position.y + story.size.y < first_choice.position.y, "Long encounter sections grow without overlaps")
	game.event_panel.reveal = 1
	await capture("encounter")
	game.event_dialog.close_dialog()
	game.province_view.close()
	game.view.cancel_level_transition()
	root.get_node("Sound").stop_all()
	game.queue_free()
	await process_frame
	sound.set_muted(original_muted, false)
	print("UI layout checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
