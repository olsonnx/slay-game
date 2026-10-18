extends RefCounted
## Concise choice tooltips retain chances, amounts, costs and lasting consequences.
const DEFAULT_PAINTING := {
	"painting": "res://assets/paintings/Jozef_Chełmoński_-_Landscape_-_Forest.png",
	"painting_title": "Landscape – Forest",
	"painting_artist": "Józef Chełmoński"
}
# Relative frequency, not a percentage. Each event has one lottery entry.
# A zero weight keeps an event available to the editor, but out of random draws.
const WEIGHTS := {
	"gold": 12, "altar": 4, "pit": 1, "duel": 5, "wizard": 5,
	"goose": 3, "comet": 4, "innkeeper": 6, "lumberjack": 8,
	"regroup": 3, "cartographer": 1,
	"ransom": 6, "economist": 6, "revolt": 2, "stainless_steel": 2
}
const EVENTS := {
	"gold": {"title": "A forgotten fortune", "text": "Beneath a crumbling milestone, your army discovers a chest of coins. Nobody remains to claim it.", "choices": [["Great!", "Gain 10–25 gold."]]},
	"altar": {"title": "The sleeping altar", "text": "An ancient altar hums beneath the moss. Its runes promise power, but the last inscription is a warning.", "choices": [["Awaken it", "60%: gain a mana source.\n40%: this army dies."], ["Leave it alone", "Nothing happens."]]},
	"pit": {"title": "One step too far", "text": "The ground gives way. A hidden pit swallows your army before anyone can throw down a rope.", "choices": [["A tragic loss", "Your army is lost."]]},
	"duel": {"title": "The warlord's challenge", "text": "A local warlord bars the road and challenges your champion. Victory would make your soldiers legends.", "choices": [["Accept the challenge", "60%: gain 1 tier (Knights gain 20 gold).\n40%: this army dies."], ["Decline politely", "Nothing happens."]]},
	"wizard": {"title": "A friend in a pointed hat", "text": "A wandering wizard shares tea with your soldiers and offers a little magic for the journey ahead.", "choices": [["Thank you, kind wizard", "Your next successful spell costs 0 mana."]]},
	"goose": {"title": "A very important goose", "text": "A goose claims to be the rightful ruler of this island. After a lengthy honk, it waddles away. Your army collects 2 gold from spectators as the first royal tax.", "requires": ["kingdom"], "choices": [["Long live the goose", "Gain 2 gold.\nThe goose remains extremely pleased."]]},
	"comet": {"title": "Comet sighted!", "text": "The priests predict disaster. The treasurer predicts revenue. The recruiting sergeant proposes recruiting volunteers inspired by the omen.", "requires": ["kingdom"], "requirements": "A connected kingdom. Recruiting volunteers also requires a clear, empty province.", "choices": [["Clearly a tax loophole.", "Permanently gain 1–2 gold per turn.\n50% chance of each."], ["Recruit the volunteers.", "Gain a ready Scout.\nNormal upkeep applies."]]},
	"innkeeper": {"requires": ["kingdom"], "title": "Innkeeper's Offer", "text": "The innkeeper insists your army try the local spirits. Declining would insult his hospitality, his ancestors, and the large man blocking the door.", "requirements": "Any army entering this province.", "choices": [["Try Headman's Last Breath.", "50%: gain 4 gold.\n50%: this army dies."], ["Try Father's Final Request.", "50%: gain 4 gold.\n50%: this army dies."]]},
	"lumberjack": {"painting": "res://assets/paintings/Franz_Steinfeld_-_Landscape_with_Group_of_Trees_and_Woodcutters.png", "painting_title": "Landscape with Group of Trees and Woodcutters", "painting_artist": "Franz Steinfeld", "overgrown_text": "Our kingdom is mostly forest, with a small administrative inconvenience attached. A lumberjack offers to find the roads. Payment, he says, would be optimistic.", "overgrown_choices": [["At least we will have a kingdom again.", "Clear your kingdom's trees.\nNo gold reward."]], "title": "Lumberjack's Offer", "text": "The royal forester has spent three months counting trees. A man with an axe offers to conclude the investigation before lunch.", "requires": ["kingdom", "forest"], "requirements": "This connected kingdom has trees. Rewards depend on how much potential income they block.", "choices": [["A promising branch of government.", "Clear your kingdom's trees.\nGain 1 gold per tree."]]},
	"regroup": {"title": "Regroup!", "text": "The marshal reports that our army is perfectly balanced, provided one ignores its composition, deployment, and continued existence. He proposes a fresh start.", "requires": ["kingdom", "multiple_units"], "requirements": "Your faction has at least two units on the board.", "choices": [["Return everyone to the recruitment office.", "Disband all your armies.\nRefund 100% of their recruitment cost."], ["The imbalance is traditional.", "Tradition wins another decisive victory."]]},
	"cartographer": {"title": "Cartographer's blunder", "text": "Our court cartographer admits the border was drawn with a wine stain as reference. The neighbouring villages have accepted his correction with suspicious enthusiasm.", "requires": ["kingdom"], "requirements": "The army belongs to a connected kingdom.", "choices": [["Revise the map. Quietly.", "This province and your neighbouring land become neutral.\nUnits and buildings there are lost."]]},
	"ransom": {"title": "A noble ransom", "text": "Your army finds a foreign royal travelling incognito, accompanied by twelve servants carrying his portrait. His family may pay handsomely for his continued discretion.", "requires": ["kingdom", "other_faction"], "requirements": "At least one other living faction remains.", "choices": [["Royalty is a liquid asset.", "Gain 20 gold."], ["Let his death demonstrate our power.", "Gain 1 mana."]]},
	"economist": {"title": "A crisis of confidence", "text": "Our court economist has lost confidence in the accounts. He proposes selling future revenue for cash, or investing cash in future revenue. The treasurer insists we choose before he changes his forecast again.", "requires": ["kingdom", "income_trade"], "requirements": "A connected kingdom with income to sell or at least 10 gold to invest. A deficit is not required.", "choices": [["Tomorrow is an accounting problem.", "Gain 10 gold.\nPermanently lose 1 gold per turn."], ["Perhaps tomorrow should have an income.", "Pay 10 gold.\nPermanently gain 1 gold per turn."]]},
	"revolt": {"title": "The Pitchfork Parliament", "text": "The peasants have formed a representative assembly. Every representative carries a pitchfork, and their first motion is that we should leave immediately.", "requires": ["kingdom", "rebel_slot"], "requirements": "An unused kingdom identity is available, and this province has neighbouring passable land.", "choices": [["Recognise their independence. From a distance.", "Rebels seize this province and neighbouring land.\nUnits there join the rebels."], ["Surely this calls for a modest subsidy.", "Pay 100% of this kingdom's gold."]]},
	"stainless_steel": {"title": "Invention of stainless steel", "text": "A smith has invented armour that refuses to rust. Our knights demand the savings be passed on to them. The treasurer has understood this request rather differently.", "requires": ["kingdom", "knights", "no_stainless_steel"], "requirements": "Your faction has a Knight and has not discovered stainless steel yet.", "choices": [["A triumph of military economy.", "Permanently reduce Knight upkeep by 2 gold."]]}

}
const EFFECTS := {
	"trailblaze": ["↠", "Trailblaze", "The next unit you move can move again if it captures neutral land. Any valid move consumes this effect. Persists until used."],
	"free_spell": ["✦", "Wizard's gift", "Your next successfully cast spell costs no mana. Persists until used."]
}

static func canonical_id(id: String) -> String:
	# Older authored maps keep working, but the editor exposes only one lumberjack.
	return "lumberjack" if id == "lumberjack_overgrown" else id
