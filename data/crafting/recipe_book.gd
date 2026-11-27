extends Resource
## Crafting recipes (Tab inventory: drag one item onto another; right-click for one-item recipes).
## Edit res://data/crafting/recipes.tres - no code changes needed.
## Each entry:
##   a, b          item ids (order doesn't matter). b = "" -> one-item recipe (right-click menu).
##                 b can be a group: "@bow" (any bow/slingshot), "@sling" (slingshot-type, not arrows), "@rod" (Rimecaller Rod),
##                 "@melee" (any blade/hammer), "@shield"
##   a_count, b_count  how many get used up (groups are never used up)
##   result, result_count   item made...
##   convert: true  up to b_count of b turn into result_count each (1 Cinderpepper + up to 5 Arrows = Fire Arrows)
##   batch: true    repeat for as many as both stacks allow (5 Bombs on 9 Arrows = 5 Bomb Arrows)
##   infuse        ...or an element put on the weapon/shield in b instead:
##                 { "element": "fire"/"frost"/"shock", "charges": shots (bows), "time": seconds (melee/shield) }

@export var recipes: Array[Dictionary] = []
