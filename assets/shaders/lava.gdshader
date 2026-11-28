shader_type spatial;
// Liquid lava (pools + flows). Thick, slow swell; molten orange that brightens in the hot middle;
// big dark crust plates drifting with the flow with glowing seams between them; a cooled crusty
// rim where it meets the shore (from the depth buffer, like the water). Light pixel snapping
// keeps the Megabonk look. Strong emission so Glow (Lighting rig) blooms off it.
// UV.y runs along a flow (LavaFlow), or world XZ for pools (world_uv).
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform vec4 hot_color : source_color = vec4(1.0, 0.62, 0.12, 1.0);
uniform vec4 mid_color : source_color = vec4(0.98, 0.36, 0.05, 1.0);
uniform vec4 deep_color : source_color = vec4(0.62, 0.1, 0.02, 1.0);
uniform vec4 crust_color : source_color = vec4(0.13, 0.06, 0.05, 1.0);
uniform float emission_strength = 1.5;
uniform float flow_speed = 0.35;          // UV units / s along a flow
uniform float pixels_per_unit = 5.0;      // chunkiness (lower = bigger pixels, 0 = smooth)
uniform float crust_amount = 0.45;        // share of the surface covered by crust plates
uniform float plate_scale = 0.55;         // bigger = smaller plates
uniform float shore_crust = 1.4;          // metres of cooled crust along the shore
uniform float swell = 0.07;               // slow vertex heave (metres)
uniform float pulse = 0.2;
uniform bool world_uv = false;
uniform float world_scale = 0.18;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}
// cellular: distance to the nearest / second-nearest feature point + the nearest cell's id
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.3));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; id = hash(i + g + 5.1); } else if (d < d2) { d2 = d; }
		}
	}
	return vec3(d1, d2, id);
}

varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (sin(world_pos.x * 0.21 + TIME * 0.45) + cos(world_pos.z * 0.17 + TIME * 0.37)) * swell;
}

void fragment() {
	vec2 uv = world_uv ? world_pos.xz * world_scale : UV * vec2(1.0, 0.5);
	vec2 drift = world_uv ? vec2(sin(TIME * 0.03), cos(TIME * 0.025)) * 1.5 : vec2(0.0, -TIME * flow_speed * 0.5);
	vec2 p = uv + drift;
	if (pixels_per_unit > 0.0) {
		p = floor(p * pixels_per_unit * 4.0) / (pixels_per_unit * 4.0);
	}
	// molten body: flowing fbm, hotter where it churns
	float n = fbm(p * 1.6 + vec2(TIME * 0.05, 0.0));
	float n2 = fbm(p * 3.4 - vec2(0.0, TIME * 0.08));
	float heat = clamp(n * 0.8 + n2 * 0.4, 0.0, 1.0);
	vec3 molten = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.25, 0.55, heat));
	molten = mix(molten, hot_color.rgb, smoothstep(0.6, 0.85, heat));
	// crust plates riding on top, seams glow
	vec3 c = cells(p * plate_scale * 3.0 + n * 0.6);
	float seam = c.y - c.x;
	float plate_id = c.z;
	float is_plate = step(1.0 - crust_amount, plate_id) * smoothstep(0.05, 0.14, seam);
	// shore: cooled crust where the lava is shallow (depth buffer)
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float thick = clamp((VERTEX.z - view.z) / max(shore_crust, 0.01), 0.0, 1.0);
	float shore = 1.0 - smoothstep(0.15, 1.0, thick + n2 * 0.25);
	if (!world_uv) {                                       // flow ribbons: crusty banks
		shore = max(shore, smoothstep(0.32, 0.5, abs(UV.x - 0.5) + n2 * 0.08));
	}
	float crust = clamp(max(is_plate * 0.9, shore), 0.0, 1.0);
	vec3 col = mix(molten, crust_color.rgb, crust);
	float hot_seam = (1.0 - smoothstep(0.0, 0.09, seam)) * step(1.0 - crust_amount - 0.15, plate_id) * (1.0 - shore);
	col = mix(col, hot_color.rgb, hot_seam * 0.9);
	float glow = (1.0 - crust) * (0.75 + heat * 0.5) + hot_seam * 0.9 + shore * 0.08;
	glow *= 1.0 + sin(TIME * 1.6 + n * 8.0) * pulse;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col * 0.4;
	EMISSION = col * emission_strength * glow;
	ROUGHNESS = mix(0.45, 0.9, crust);                    // molten parts are a bit glossy, crust is dull
	SPECULAR = 0.12 + fres * 0.12;
	ALPHA = 0.99;
}
