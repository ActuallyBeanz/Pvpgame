shader_type spatial;
// Stylised water: gentle vertex swell, depth-faded colour, fresnel rim, sparkle bands.
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.25, 0.7, 0.85, 0.55);
uniform vec4 deep_color : source_color = vec4(0.06, 0.28, 0.55, 0.85);
uniform float depth_fade = 6.0;
uniform float wave_height = 0.12;
uniform float wave_speed = 0.8;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(w.x * 0.15 + TIME * wave_speed) * wave_height + cos(w.z * 0.11 + TIME * wave_speed * 0.8) * wave_height;
}

void fragment() {
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float water_depth = clamp((VERTEX.z - view.z) / depth_fade, 0.0, 1.0);
	vec4 col = mix(shallow_color, deep_color, water_depth);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sparkle = step(0.97, sin(wp.x * 0.9 + TIME * 1.3) * sin(wp.z * 0.8 - TIME * 1.1));
	ALBEDO = col.rgb + vec3(fres * 0.25) + vec3(sparkle * 0.3);
	ALPHA = clamp(col.a + fres * 0.3, 0.0, 0.95);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
}
