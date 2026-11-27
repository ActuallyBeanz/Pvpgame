extends RefCounted
## Builds the hover tooltip for an item (inventory slots, arrow wheel), all from data:
##   name + type line, ItemDef.description, the element's effect (WorldRules element_info),
##   stats that matter (heal, damage x, stack size), what it combines into (recipes.tres),
##   and the infusion currently on it. New items / recipes explain themselves.

const GROUP_NAMES := {
	"@bow": "a bow or slingshot", "@sling": "the slingshot", "@melee": "a blade or hammer",
	"@shield": "a shield", "@rod": "the Rimecaller Rod",
}


static func type_line(it: Resource) -> String:
	if it.category == "brew":
		return "Brew vial · throw it (LMB), shatters on impact"
	match it.kind:
		"ammo":
			return "Ammo" + ("" if it.ammo_family == "" else " · special arrow")
		"shield":
			return "Shield · RMB / F to block"
		"material":
			return {"reagent": "Plant (reagent)", "food": "Food", "ore": "Ore"}.get(it.category, "Material")
	return "Weapon" + (" · %s" % it.category if it.category != "" else "")


static func effect_of(element: String) -> String:
	return str(WorldRules.rules.element_info.get(element, "")) if element != "" else ""


## BBCode text for the tooltip.
static func build(equipment: Node, id: String) -> String:
	var it: Resource = ItemDB.get_item(id)
	if it == null:
		return ""
	var col: Color = WorldRules.element_color(it.element) if it.element != "" else Color(1, 0.92, 0.7)
	var t := "[font_size=18][b][color=#%s]%s[/color][/b][/font_size]\n" % [col.to_html(false), it.display_name]
	t += "[color=#aab]%s[/color]\n" % type_line(it)
	if it.description != "":
		t += "\n%s\n" % it.description
	# what it does
	var fx := effect_of(it.element)
	if fx != "" and (it.kind == "ammo" or it.category == "brew"):
		t += "\n[color=#%s]Effect:[/color] %s\n" % [col.to_html(false), fx]
	if it.kind == "ammo" and it.damage_mult != 1.0:
		t += "[color=#aab]Arrow damage x%.1f[/color]\n" % it.damage_mult
	if it.explosive:
		t += "[color=#ffb070]Explodes on impact. Fuse lights when you draw - fire it within %.0f s![/color]\n" % it.fuse_time
	if it.heal > 0.0:
		t += "\n[color=#8f8]Eat (right-click): +%d health[/color]\n" % roundi(it.heal)
	# infusion on this weapon right now
	if equipment and equipment.infusions.has(id):
		var inf: Dictionary = equipment._infusion(id)
		if not inf.is_empty():
			var e: String = inf.element
			var left := ("%d shots" % int(inf.charges)) if float(inf.until) <= 0.0 \
				else ("%d s" % ceili(float(inf.until) - Time.get_ticks_msec() / 1000.0))
			t += "\n[color=#%s]Infused: %s (%s)[/color] - %s\n" % [WorldRules.element_color(e).to_html(false), e.capitalize(), left, effect_of(e)]
	# recipes it's part of
	var uses := _recipe_lines(id, it)
	if not uses.is_empty():
		t += "\n[color=#cdf]Combine (drag onto):[/color]\n"
		for u in uses:
			t += "  • %s\n" % u
	return t.strip_edges()


static func _matches(token: String, id: String, it: Resource) -> bool:
	match token:
		"@bow":
			return it.kind == "weapon" and it.action_tag == "shoot"
		"@sling":
			return it.kind == "weapon" and it.action_tag == "shoot" and it.ammo_item_id != "arrows"
		"@melee":
			return it.kind == "weapon" and it.action_tag == "slash"
		"@shield":
			return it.kind == "shield"
		"@rod":
			return it.kind == "weapon" and it.action_tag == "rod"
	return token == id


static func _name(token: String) -> String:
	if GROUP_NAMES.has(token):
		return GROUP_NAMES[token]
	var it: Resource = ItemDB.get_item(token)
	return it.display_name if it else token


static func _recipe_lines(id: String, it: Resource) -> Array[String]:
	var out: Array[String] = []
	var book: Resource = load("res://data/crafting/recipes.tres")
	for r: Dictionary in book.recipes:
		var a: String = r.get("a", "")
		var b: String = r.get("b", "")
		var other := ""
		if _matches(a, id, it):
			other = b
		elif b != "" and _matches(b, id, it):
			other = a
		else:
			continue
		var what := ""
		if r.has("infuse"):
			var inf: Dictionary = r.infuse
			var e: String = inf.element
			var how := ("%d shots" % int(inf.charges)) if int(inf.get("charges", 0)) > 0 else ("%d s" % int(inf.get("time", 0)))
			what = "%s infusion (%s)" % [e.capitalize(), how]
		else:
			var res: Resource = ItemDB.get_item(str(r.get("result", "")))
			var n := int(r.get("result_count", 1))
			var rname: String = res.display_name if res else str(r.get("result", ""))
			if bool(r.get("convert", false)):
				what = "up to %d %s" % [int(r.get("b_count", 1)), rname]
			else:
				what = ("%s x%d" % [rname, n]) if n > 1 else rname
		if other == "":
			out.append("right-click > Make: %s" % what)
		else:
			out.append("%s  →  %s" % [_name(other), what])
	return out
