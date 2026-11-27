shader_type spatial;
// Pixel-art lava: chunky flowing cells, a dark cooling crust that drifts with the flow, bright
// cracks that pulse. Strong emission so the glow (Lighting > Glow) blooms off it.
// UV.y runs along the flow (LavaFlow), or world XZ for pools (world_uv).
render_mode specular_disabled, cull_disabled;

uniform vec4 hot_color : source_color = vec4(1.0, 0.66, 0.16, 1.0);
uniform vec4 mid_color : source_color = vec4(0.92, 0.24, 0.03, 1.0);
uniform vec4 crust_color : source_color = vec4(0.16, 0.07, 0.05, 1.0);
uniform float emission_strength = 1.7;
uniform float flow_speed = 0.35;          // UV units per second along the flow
uniform float pixels_per_unit = 12.0;     // chunkiness (lower = bigger pixels)
uniform float crust_amount = 0.6;         // 0 = all molten, 1 = mostly crust
uniform float pulse = 0.25;
uniform bool world_uv = false;            // pools: use world XZ (and swirl slowly)
uniform float world_scale = 0.35;

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

varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_uv ? world_pos.xz * world_scale : UV * vec2(1.0, 1.0);
	vec2 flow = world_uv ? vec2(sin(TIME * 0.05), cos(TIME * 0.04)) * TIME * 0.02 : vec2(0.0, -TIME * flow_speed);
	vec2 q = floor((uv + flow) * pixels_per_unit) / pixels_per_unit;       // pixel snap
	float n = fbm(q * vec2(2.2, 1.2) + vec2(0.0, 0.0));
	float n2 = fbm(q * 4.0 + vec2(TIME * 0.07, 0.0));
	float heat = clamp(n * 0.7 + n2 * 0.5, 0.0, 1.0);
	vec3 col = mix(hot_color.rgb, mid_color.rgb, smoothstep(0.35, 0.6, heat));
	float th = 0.78 - crust_amount * 0.35;
	float crust = step(th, n + n2 * 0.15);
	// molten cracks between crust plates glow hotter
	float crack = 1.0 - smoothstep(0.0, 0.03, abs(n + n2 * 0.15 - th));
	col = mix(col, crust_color.rgb, crust);
	col = mix(col, hot_color.rgb, crack * 0.8);
	float glow = (1.0 - crust) + crack * 0.6;
	glow *= 1.0 + sin(TIME * 2.0 + n * 9.0) * pulse;
	// fade the molten edge of a flow ribbon into crust
	if (!world_uv) {
		float edge = 1.0 - smoothstep(0.32, 0.5, abs(UV.x - 0.5));
		col = mix(crust_color.rgb, col, edge);
		glow *= edge;
	}
	ALBEDO = col * 0.35;
	EMISSION = col * emission_strength * glow;
	ROUGHNESS = 0.85;
}
