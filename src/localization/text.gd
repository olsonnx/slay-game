extends RefCounted
## Translate before substituting dynamic values. English messages are stable keys.

static func text(message: String) -> String:
	return String(TranslationServer.translate(message)) if not message.is_empty() else message

static func placeholders(message: String) -> Array[String]:
	var pattern := RegEx.new()
	pattern.compile("%[-+0 #]*[0-9]*(?:\\.[0-9]+)?[sdifxXoOcveEgG]")
	var result: Array[String] = []
	for match_value in pattern.search_all(message.replace("%%", "")):
		result.append(match_value.get_string())
	return result

static func named_placeholders(message: String) -> Array[String]:
	var pattern := RegEx.new()
	pattern.compile("\\{[a-zA-Z_][a-zA-Z_0-9]*\\}")
	var result: Array[String] = []
	for match_value in pattern.search_all(message):
		result.append(match_value.get_string())
	result.sort()
	return result

static func valid_translation(source: String, translated: String) -> bool:
	if placeholders(source) != placeholders(translated) or named_placeholders(source) != named_placeholders(translated): return false
	if not placeholders(source).is_empty():
		var pattern := RegEx.new()
		pattern.compile("%(?:%|[-+0 #]*[0-9]*(?:\\.[0-9]+)?[sdifxXoOcveEgG])")
		if pattern.sub(translated, "", true).contains("%"): return false
	return true
