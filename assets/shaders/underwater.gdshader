shader_type canvas_item;
// Full-screen underwater look (camera below the water surface): wobbly refraction, blue-green
// tint that thickens toward the edges, faint moving caustic light.
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform vec4 tint : source_color = vec4(0.12, 0.42, 0.62, 1.0);
uniform float tint_amount = 0.5;
uniform float wobble = 0.004;
uniform float vignette = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 34.0 + TIME * 2.1), cos(uv.x * 27.0 + TIME * 1.7)) * wobble;
	vec3 col = texture(screen, uv).rgb;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, tint.rgb * (0.55 + lum * 0.9), tint_amount);
	float c = sin(uv.x * 40.0 + TIME * 1.3) * sin(uv.y * 31.0 - TIME * 1.1);
	col += tint.rgb * smoothstep(0.75, 1.0, c) * 0.12;
	float v = smoothstep(0.85, 0.2, distance(SCREEN_UV, vec2(0.5)));
	col *= mix(1.0 - vignette, 1.0, v);
	COLOR = vec4(col, 1.0);
}
