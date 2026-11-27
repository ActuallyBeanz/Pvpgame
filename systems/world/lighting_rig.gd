@tool
extends Node3D
## One node for the whole look of a map: sky, sun, fog + light shafts, glow, ambient occlusion,
## bounce light and colour grading. Select it and tweak in the Inspector - changes show live in
## the editor. Pick a `preset` to load a starting point, then fine tune.
## Builds its own WorldEnvironment + sun at runtime / in the editor (nothing else to wire up).

enum Preset { CUSTOM, GOLDEN_AFTERNOON, BRIGHT_NOON, DUSK, OVERCAST, VOLCANIC_HAZE }

@export var preset: Preset = Preset.GOLDEN_AFTERNOON:
	set(v):
		preset = v
		if v != Preset.CUSTOM:
			_apply_preset(v)
		_rebuild()

@export_group("Sun")
@export var sun_color := Color(1.0, 0.9, 0.76)
@export_range(0.0, 4.0, 0.01) var sun_energy := 1.35
@export_range(-10.0, 90.0, 0.5) var sun_elevation_deg := 36.0
@export_range(-180.0, 180.0, 0.5) var sun_azimuth_deg := 35.0
@export_range(10.0, 600.0, 1.0) var shadow_distance := 180.0
@export_range(0.0, 1.0, 0.01) var shadow_softness := 0.35

@export_group("Sky")
@export var sky_top := Color(0.24, 0.47, 0.92)
@export var sky_horizon := Color(0.78, 0.86, 0.96)
@export var ground_horizon := Color(0.6, 0.68, 0.72)
@export var ground_bottom := Color(0.12, 0.22, 0.32)
@export_range(0.0, 3.0, 0.01) var sky_energy := 1.0
@export_range(0.0, 3.0, 0.01) var ambient_energy := 1.0

@export_group("Fog")
@export var fog_enabled := true
@export var fog_color := Color(0.74, 0.83, 0.94)
@export_range(0.0, 0.02, 0.0001) var fog_density := 0.0009
@export_range(0.0, 1.0, 0.01) var fog_sun_scatter := 0.25
@export_range(-1.0, 1.0, 0.01) var fog_height_density := 0.0   ## > 0: thicker low down
@export var fog_height := -2.0
@export_subgroup("Light shafts (volumetric)")
@export var volumetric_enabled := true
@export_range(0.0, 0.1, 0.0005) var volumetric_density := 0.004
@export var volumetric_albedo := Color(0.92, 0.94, 1.0)
@export_range(0.0, 1.0, 0.01) var volumetric_anisotropy := 0.6   ## forward scatter = shafts toward the sun
@export_range(20.0, 300.0, 1.0) var volumetric_length := 90.0

@export_group("Glow (emissive bloom)")
@export var glow_enabled := true
@export_range(0.0, 4.0, 0.01) var glow_intensity := 0.85
@export_range(0.0, 2.0, 0.01) var glow_strength := 1.0
@export_range(0.0, 1.0, 0.01) var glow_bloom := 0.04
@export_range(0.0, 4.0, 0.01) var glow_threshold := 0.95

@export_group("Shading")
@export var ssao_enabled := true
@export_range(0.0, 4.0, 0.01) var ssao_intensity := 1.4
@export var ssil_enabled := true          ## cheap bounce light
@export var sdfgi_enabled := false        ## real global illumination (heavier)

@export_group("Colour grading")
@export_enum("Linear", "Reinhard", "Filmic", "ACES", "AgX") var tonemap := 4
@export_range(0.1, 4.0, 0.01) var exposure := 1.05
@export_range(0.5, 2.0, 0.01) var saturation := 1.15
@export_range(0.5, 2.0, 0.01) var contrast := 1.06
@export_range(0.5, 2.0, 0.01) var brightness := 1.0

var _env: WorldEnvironment
var _sun: DirectionalLight3D


func _ready() -> void:
	_rebuild()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild()                               # live preview while you drag sliders


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _env == null:
		_env = WorldEnvironment.new()
		_env.name = "Env"
		add_child(_env)
		_env.environment = Environment.new()
		var sky := Sky.new()
		sky.sky_material = ProceduralSkyMaterial.new()
		_env.environment.sky = sky
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "Sun"
		add_child(_sun)
	var e := _env.environment
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = sky_top
	sm.sky_horizon_color = sky_horizon
	sm.ground_horizon_color = ground_horizon
	sm.ground_bottom_color = ground_bottom
	sm.sky_energy_multiplier = sky_energy
	sm.sun_angle_max = 30.0
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = ambient_energy
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = tonemap
	e.tonemap_exposure = exposure
	e.fog_enabled = fog_enabled
	e.fog_light_color = fog_color
	e.fog_density = fog_density
	e.fog_sun_scatter = fog_sun_scatter
	e.fog_height_density = fog_height_density
	e.fog_height = fog_height
	e.volumetric_fog_enabled = volumetric_enabled and fog_enabled
	e.volumetric_fog_density = volumetric_density
	e.volumetric_fog_albedo = volumetric_albedo
	e.volumetric_fog_anisotropy = volumetric_anisotropy
	e.volumetric_fog_length = volumetric_length
	e.glow_enabled = glow_enabled
	e.glow_intensity = glow_intensity
	e.glow_strength = glow_strength
	e.glow_bloom = glow_bloom
	e.glow_hdr_threshold = glow_threshold
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.ssao_enabled = ssao_enabled
	e.ssao_intensity = ssao_intensity
	e.ssil_enabled = ssil_enabled
	e.sdfgi_enabled = sdfgi_enabled
	e.adjustment_enabled = true
	e.adjustment_saturation = saturation
	e.adjustment_contrast = contrast
	e.adjustment_brightness = brightness
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sun.shadow_enabled = true
	_sun.shadow_blur = 0.5 + shadow_softness * 2.5
	_sun.directional_shadow_max_distance = shadow_distance
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.light_volumetric_fog_energy = 1.2
	_sun.rotation = Vector3(deg_to_rad(-sun_elevation_deg), deg_to_rad(sun_azimuth_deg), 0.0)


func _apply_preset(p: Preset) -> void:
	match p:
		Preset.GOLDEN_AFTERNOON:
			_set_all(Color(1.0, 0.9, 0.76), 1.35, 36.0, Color(0.24, 0.47, 0.92), Color(0.78, 0.86, 0.96),
				Color(0.74, 0.83, 0.94), 0.0009, 0.004, 1.15, 1.05)
		Preset.BRIGHT_NOON:
			_set_all(Color(1.0, 0.98, 0.94), 1.5, 68.0, Color(0.2, 0.45, 0.95), Color(0.72, 0.84, 0.98),
				Color(0.78, 0.86, 0.96), 0.0011, 0.003, 1.2, 1.1)
		Preset.DUSK:
			_set_all(Color(1.0, 0.62, 0.38), 1.1, 9.0, Color(0.18, 0.2, 0.42), Color(0.98, 0.62, 0.42),
				Color(0.86, 0.56, 0.46), 0.0028, 0.012, 1.2, 0.95)
		Preset.OVERCAST:
			_set_all(Color(0.86, 0.9, 0.96), 0.7, 50.0, Color(0.5, 0.56, 0.64), Color(0.72, 0.76, 0.8),
				Color(0.7, 0.74, 0.78), 0.004, 0.008, 0.9, 1.0)
		Preset.VOLCANIC_HAZE:
			_set_all(Color(1.0, 0.7, 0.5), 1.1, 24.0, Color(0.32, 0.26, 0.3), Color(0.86, 0.56, 0.42),
				Color(0.62, 0.42, 0.36), 0.005, 0.02, 1.1, 0.95)


func _set_all(sc: Color, se: float, elev: float, top: Color, hor: Color, fog: Color, fd: float, vd: float,
		sat: float, expo: float) -> void:
	sun_color = sc
	sun_energy = se
	sun_elevation_deg = elev
	sky_top = top
	sky_horizon = hor
	fog_color = fog
	fog_density = fd
	volumetric_density = vd
	saturation = sat
	exposure = expo
