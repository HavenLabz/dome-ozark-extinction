shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Ozark ground: colors chosen by slope and height so cliffs read as rock,
// flats as grass, shorelines as sand — with procedural patchiness for realism.
// No texture assets required (zero-cost art direction).

uniform vec3 grass_low : source_color = vec3(0.11, 0.19, 0.08);
uniform vec3 grass_high : source_color = vec3(0.28, 0.40, 0.16);
uniform vec3 grass_dry : source_color = vec3(0.40, 0.40, 0.19);
uniform vec3 dirt : source_color = vec3(0.30, 0.23, 0.14);
uniform vec3 rock : source_color = vec3(0.29, 0.27, 0.24);
uniform vec3 rock_high : source_color = vec3(0.40, 0.39, 0.37);
uniform vec3 sand : source_color = vec3(0.56, 0.50, 0.34);
uniform float water_level = -1.5;
uniform float patch_scale = 0.06;

varying vec3 w_pos;
varying vec3 w_norm;

// cheap value noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = clamp(w_norm.y, 0.0, 1.0);         // 1 = flat, 0 = vertical
	float h = w_pos.y;
	// Multi-scale noise: macro patches, meso mottle, and fine grain so the ground
	// has texture right up to the camera instead of reading as a flat sheet.
	float macro = fbm(w_pos.xz * patch_scale);
	float meso  = fbm(w_pos.xz * patch_scale * 4.0);
	float fine  = fbm(w_pos.xz * patch_scale * 22.0);
	float micro = noise(w_pos.xz * patch_scale * 90.0);

	// Base grass: strong low↔high variation, broken up by fine grain.
	float gmix = clamp(macro * 0.7 + fine * 0.3, 0.0, 1.0);
	vec3 col = mix(grass_low, grass_high, gmix);
	// Sun-bleached dry patches in the open.
	col = mix(col, grass_dry, smoothstep(0.62, 0.9, macro) * 0.4);
	// Bare dirt where the meso noise clusters (worn ground / trails).
	col = mix(col, dirt, smoothstep(0.58, 0.8, meso) * 0.6);
	// Fine grain darkens/lightens each patch of turf so it never looks uniform.
	col *= mix(0.82, 1.12, fine);
	col *= mix(0.94, 1.06, micro);

	// Rock on steep slopes.
	float rock_f = smoothstep(0.78, 0.55, slope);
	vec3 rockcol = mix(rock, rock_high, clamp((h + 4.0) / 12.0, 0.0, 1.0));
	rockcol *= mix(0.8, 1.1, fine);
	col = mix(col, rockcol, rock_f);

	// Sand near the waterline.
	float sand_f = smoothstep(water_level + 1.8, water_level + 0.1, h);
	col = mix(col, sand * mix(0.85, 1.1, micro), sand_f * step(slope, 0.95) * 0.9);

	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.7, rock_f);
	SPECULAR = 0.18;
}
