shader_type canvas_item;
// The garden floor: soft cloud shadows drift across it and ponds and rivers
// shimmer. Water is found by colour (clearly blue pixels), so every map works
// without a hand-made mask.

uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform vec2 world_size = vec2(2160.0, 1320.0);
uniform float clouds = 0.12;  // how dark a cloud's shadow gets (0 = no clouds)
uniform float water = 1.0;  // shimmer strength (0 = still water)

// 1 on a thin line where the noise crosses the middle, 0 elsewhere
float ridge(float n, float sharp) {
	return pow(1.0 - abs(n * 2.0 - 1.0), sharp);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 w = UV * world_size;
	float shade = 0.0;
	if (clouds > 0.0) {
		float n = texture(noise, w / 1700.0 + vec2(TIME * 0.0042, TIME * 0.0017)).r * 0.65
			+ texture(noise, w / 900.0 + vec2(-TIME * 0.0028, TIME * 0.0031)).r * 0.35;
		shade = smoothstep(0.5, 0.7, n) * clouds;
	}
	float wm = smoothstep(0.2, 0.32, c.b - c.r) * smoothstep(0.55, 0.45, c.r) * smoothstep(-0.04, 0.02, c.b - c.g);
	if (wm > 0.001 && water > 0.0) {
		vec2 q = w / 260.0;
		float a = texture(noise, q + vec2(TIME * 0.035, TIME * 0.012)).r;
		float b = texture(noise, q * 1.37 + vec2(-TIME * 0.027, TIME * 0.022)).r;
		// a net of bright ripple lines where the two drifting layers' ridges meet
		float lines = ridge(a, 10.0) * 0.6 + ridge(b, 12.0) * 0.5;
		lines = lines * lines;
		float glint = pow(texture(noise, w / 70.0 + vec2(TIME * 0.06, -TIME * 0.04)).r, 9.0) * 1.6;
		vec3 add = vec3(0.75, 0.93, 1.0) * (lines * 0.32 + glint * 0.5);
		c.rgb = mix(c.rgb, c.rgb * (0.93 + a * 0.1) + add, wm * water);
	}
	c.rgb *= 1.0 - shade * vec3(1.0, 0.9, 0.72);  // cool, bluish shade
	COLOR = c;
}
