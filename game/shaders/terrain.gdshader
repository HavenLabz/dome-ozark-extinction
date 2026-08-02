shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Ozark ground with real PBR textures (Poly Haven, CC0): forest floor on the
// flats, worn dirt in the hollows, rock on the cliffs — blended by slope and
// height, world-projected (no UVs needed) with triplanar on steep faces so the
// ground reads as real terrain up close. Grass tufts (MultiMesh) layer on top.

uniform sampler2D grass_tex : source_color;
uniform sampler2D dirt_tex : source_color;
uniform sampler2D rock_tex : source_color;
uniform sampler2D grass_rough;
uniform sampler2D dirt_rough;
uniform sampler2D rock_rough;
uniform sampler2D grass_nrm;
uniform sampler2D dirt_nrm;
uniform sampler2D rock_nrm;
uniform float normal_strength = 0.8;
uniform vec3 grass_tint : source_color = vec3(0.72, 0.85, 0.5);  // nudge the floor greener
uniform vec3 sand : source_color = vec3(0.58, 0.52, 0.36);
uniform float tex_scale = 0.14;     // texture tiles per metre
uniform float water_level = -1.5;
uniform float patch_scale = 0.06;

varying vec3 w_pos;
varying vec3 w_norm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
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
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}

// Triplanar sample for steep faces where a flat top-projection would smear.
vec3 tri(sampler2D t, vec3 p, vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	return texture(t, p.zy).rgb * b.x + texture(t, p.xz).rgb * b.y + texture(t, p.xy).rgb * b.z;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = clamp(w_norm.y, 0.0, 1.0);   // 1 = flat, 0 = vertical
	float h = w_pos.y;
	vec3 sp = w_pos * tex_scale;

	// Two-scale sampling to hide obvious tiling.
	vec3 g_tex = mix(texture(grass_tex, sp.xz).rgb, texture(grass_tex, sp.xz * 0.37).rgb, 0.4);
	vec3 d_tex = texture(dirt_tex, sp.xz).rgb;
	float g_r = texture(grass_rough, sp.xz).r;
	float d_r = texture(dirt_rough, sp.xz).r;
	vec3 rk_tex = tri(rock_tex, sp, w_norm);
	float rk_r = tri(rock_rough, sp, w_norm).r;

	float macro = fbm(w_pos.xz * patch_scale);
	float meso = fbm(w_pos.xz * patch_scale * 4.0);

	// Grass/forest floor, nudged green, with large-scale light variation.
	vec3 col = g_tex * grass_tint * mix(0.82, 1.15, macro);
	float rough_v = g_r;

	// Worn dirt in the hollows.
	float dirt_f = smoothstep(0.55, 0.82, meso) * 0.75;
	col = mix(col, d_tex, dirt_f);
	rough_v = mix(rough_v, d_r, dirt_f);

	// Rock on the steep faces.
	float rock_f = smoothstep(0.8, 0.5, slope);
	col = mix(col, rk_tex, rock_f);
	rough_v = mix(rough_v, rk_r, rock_f);

	// Sandy shoreline.
	float sand_f = smoothstep(water_level + 1.8, water_level + 0.1, h) * step(slope, 0.95);
	col = mix(col, mix(d_tex, sand, 0.6), sand_f * 0.9);

	// Blend the tangent-space normals the same way, then tilt the world normal.
	// (Ground is near +Y, so map the normal-map XY onto the world XZ plane — an
	// approximation that's exact on flats and good enough on slopes.)
	vec3 gn = texture(grass_nrm, sp.xz).xyz * 2.0 - 1.0;
	vec3 dn = texture(dirt_nrm, sp.xz).xyz * 2.0 - 1.0;
	vec3 rn = tri(rock_nrm, sp, w_norm) * 2.0 - 1.0;
	vec3 nmap = mix(gn, dn, dirt_f);
	nmap = mix(nmap, rn, rock_f);
	vec3 world_n = normalize(w_norm + vec3(nmap.x, 0.0, nmap.y) * normal_strength);

	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	ROUGHNESS = clamp(rough_v, 0.45, 1.0);
	SPECULAR = 0.2;
}
