# Island (M3) — progress log
Repaint the island: edit art_src/map/make_island_maps.py (layout numbers) and re-run
  python3 art_src/map/make_island_maps.py assets/maps/island
or paint assets/maps/island/heightmap.png (grey = height: -8 m + value x 0.25 m) and biome.png
(colours listed in the script / island_terrain.gd PALETTE) by hand. Layout numbers that both the
generator and scenes/match/island.gd use (centre, landmarks, lakes, paths) must match.

## M3a island — done (untested in Godot)
- [x] heightmap.png / biome.png generator, preview at art_src/map/preview.png
- [x] systems/world/island_terrain.gd: low-poly chunks + HeightMapShape3D, height_at/biome_at/slope_deg
- [x] Water autoload (sea, lakes, frozen lake, lava) + water shader
- [x] scenes/match/island.tscn/.gd: Wellspring plaza+fountain, Frosthollow keep, Emberfall fortress,
      Sunscorch temple, 2 Thornwood ruin circles, auto bridges where paths cross water,
      cover along paths, trees/rocks scatter, 12 spawns (>=100 m), ground loot by rarity tier
- [x] Main menu: "Host (Island)" / "Host Test Arena"

## Round 2 (2026-11-25) — done (untested in Godot)
- [x] Landmark structures switched off (island.gd build_landmarks = false); their spots stay clear for custom models
- [x] Escape ramps cut into every river bank (~40 m, alternating sides) and the moat; gentler coast + more beaches
- [x] More rolling hills; test islet in the SW corner (every item on infinite stands, dummies, torch, brazier,
      ice, crates, archery targets, purple grapple pillar + dummy). spawn_on_test_islet = true (dev) puts everyone there
- [x] Swimming: Ctrl = swim down, Space = swim up / hop out at the surface; items usable at the surface, off underwater
- [x] art_src/nature/make_nature.py -> assets/models/nature: 11 trees/cactus, 9 rocks, 14 ground plants, 4 path stones
- [x] Biome-based scatter (tree_sets / rock_sets / cover_sets / forage_sets in island.gd), MultiMesh grass with
      view distance, flagstones along paths, herbs/food/ore growing naturally (Pickup.natural)

## Round 3 (2026-11-25) — done (untested in Godot)
- [x] Test islet removed from the island (build_test_islet = false); "Host Test Arena" gets a stand for every item automatically
- [x] Chests: 4 tier models (art_src/items/make_items_chests.py), scenes/props/loot/chest.gd (E to open, host rolls loot,
      lid opens + items pop out for everyone). island.gd chest_counts / chest_loot / chest_rolls; richer tiers lean central
- [x] Lobby.match_seed: chest spots, loose loot and forage move every match
- [x] Bombs (OoT): bomb_tool.gd + bomb_projectile.gd, 5 per pickup; Wood item + punching trees (bare hands)
- [x] Melee: jump attack, shield poke, Biggoron greatsword (2H), Megaton-style hammer (2H, slam + shockwave)
- [x] Headshots (arrows/slingstones x headshot_mult), swim dash (Shift), bow/slingshot start with 10 ammo

## Next
- [x] M3b swimming (Motor SWIM/DIVE states): float + stroke, hold Jump = dive while you have
      breath, release = float up, swim into a low bank = climb out, weapons put away, lit nocked
      arrow doused, fire arrows doused flying into water, shallow water slows walking, breath bar
      (HUD). Out of breath -> Motor.drowning signal (no damage until the health system exists).
      New clips OoT_Swim / OoT_Tread in oot_moves.glb. Tuning: movement_profile "Swimming".
- [ ] M3d bombable walls (secret chests, shortcuts) — bombs themselves are done
- [ ] M3e gatherable stone / wood / flint + starter weapon crafting (Tab drag)
