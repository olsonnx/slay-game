# Translating the game

The game now supports language packs. **Only the existing English text is supplied.** The other-language template is intentionally blank.

## Add your language

1. Copy `localization/template.json` to a new file in `localization/languages`, for example `pl.json` for locale code `pl`.
2. Fill in `locale` with the language code and `name` with the name you want displayed in the language selector. Keep `font` empty unless you supply a font.
3. Translate the **values on the right** inside `messages`. Keep the English keys on the left unchanged. You can leave any value empty; it will display in English until you fill it in.
4. Add the pack's path to `localization/languages.json`. For that example, its contents would be:

   ```json
   [
     "res://localization/languages/pl.json"
   ]
   ```

5. Launch the game, open **Options → Gameplay → Language**, choose your pack, and relaunch the game. The choice is saved separately from your rules and matches.

Adding a pack does not make the game switch to it automatically. English is the initial default. Selecting another language during a match does not reset or change that match; the selection takes effect the next time the application starts. Removing a selected pack restores English on the following launch.

Use UTF-8 when saving JSON. A JSON-aware editor is useful for quotation marks and line breaks. A message containing `\n` has a line break; keep it as `\n` inside the JSON string. Escape quotation marks inside text as `\"`.

## Files to edit

| File | Purpose |
|---|---|
| `localization/template.json` | Blank copy of every source entry; copy it before translating. Regeneration replaces this file. |
| `localization/languages/<your-code>.json` | Your actual translations. These are preserved by the catalogue tools. |
| `localization/languages.json` | List of the language packs installed with the game. English is always available. |
| `localization/languages/en.json` | Generated English reference. Edit source code to change English wording. |
| `localization/references.json` | Source file and line references for each message, useful when you need context. |

The catalogue covers menus, options, controls, the editor, tutorial text, encounters, unit/building/spell descriptions, tooltips, status messages and formatted HUD text. Native file-explorer captions and special key names are included too. Internal command IDs, save-file fields and faction IDs stay unchanged. User-authored map titles and player names remain user content, rather than translation keys. Built-in faction names are treated as proper names.

There may be short entries shared by several screens, or reference entries that are only used under particular rules. Use `references.json` to see where an entry comes from.

## Numbers and other placeholders

Some messages contain `%s`, `%d`, `%02d` or `%+d`. These receive names and numbers during play. Preserve **the same placeholder types and order**, including signs and width specifications. You can change the words around them. In a formatted message, a literal percent sign must be written as `%%`.

If a placeholder is missing or changed, that translation is skipped and the English message is used. Unknown keys and non-text values are also skipped. Empty values are accepted as unfinished translations.

Future messages may use named placeholders such as `{unit}` and `{place}`. Those can be reordered while retaining all the names. Existing messages mainly use ordered `%` placeholders. JSON packs provide message-by-message substitutions, not language-specific grammatical plural rules; rephrase count captions if needed, or add a dedicated source message when different grammatical forms are required.

Short menu/card captions have less room than paragraphs. Tutorial paragraphs, inspector details and tooltips measure the displayed translation and wrap it. Check your own translations at the minimum window size as well as your normal size. Font coverage, unusually long captions and right-to-left layouts need checking with the actual language; a blank template cannot establish those visually.

## Optional font

Put a font you are permitted to distribute under `localization/fonts`, then set the pack's `font` to its `res://` path. TTF and OTF files are loaded directly, so they work in both the editor and an exported build. For example, `res://localization/fonts/your-font.ttf` is a path, not a supplied font. No additional font ships with this change.

The selected font is inherited by interface controls and shared themes. Leave the field blank to use the game's default font. A missing or invalid font records a diagnostic and leaves the default available.

## Check your work

Run the validator with the Godot console executable:

```powershell
godot --headless --path . --script tools/check_translations.gd
```

It lists installed packs and reports invalid files, duplicate language codes, unknown messages and broken placeholders. An incomplete pack with empty values is valid. If your environment restricts the normal application-data directory, supply an absolute writable `--log-file` path as well.

The existing `tools/run_tests.ps1` runner includes the localization regression suite. Its temporary marker strings exercise selection, persistence, UTF-8, fallbacks, formatting, native UI integration and editor IDs. They are test fixtures, not a language pack offered to players.

## When English text changes

Regenerate the English source, blank template and references:

```powershell
python tools/localization_catalog.py
```

Synchronize your existing pack with the new source messages:

```powershell
python tools/localization_catalog.py --sync localization/languages/pl.json
```

This preserves your existing translations, adds new entries with empty values, and retains translations whose English keys disappeared under `obsolete_messages`. That section is ignored at runtime. A changed English sentence is a new key; consult the obsolete section to reuse your earlier wording where appropriate. Keep a backup or use version control for your language files.

To check that generated files match the current source without rewriting them:

```powershell
python tools/localization_catalog.py --check
```

## Exports

The enabled **Localization export** editor plugin automatically adds the language manifest, English reference and registered JSON packs to exported games. It also includes fonts named by those packs. The editable template and reference index are development files and are not added by that plugin. Keep the plugin enabled when exporting; simply copying JSON beside an exported executable does not register a new pack.

## Adding new text in code

Use the existing shared UI helpers for ordinary labels. Native Godot controls translate their literal text too. For generated text, translate the template **before** formatting it:

```gdscript
const Loc = preload("res://src/localization/text.gd")
label.text = Loc.text("Level %d") % level
```

Translate data-driven pieces before inserting them into another message; preserve player-authored values. For new text that needs flexible word order, named placeholders are available:

```gdscript
label.text = Loc.text("{unit} at {place}").format({"unit": unit_name, "place": place_name})
```

Do not translate values used for rules, filenames, dictionary keys, input actions, editor tools or saves. The display can translate a tool's name while its command continues using the original ID. Run catalogue generation after source changes, then run the validator and affected UI tests.
