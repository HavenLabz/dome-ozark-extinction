shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Wind-swayed foliage for tree canopies and grass. Tops sway more than bases;
// each instance gets a different phase from its world position, so a field of
// grass or trees moves organically. Vertical color gradient for depth.

uniform vec3 color_bottom : source_color = vec3(0.10, 0.22, 0.10);
uniform vec3 color_top : source_color = vec3(0.28, 0.45, 0.20);
uniform float sway_strength = 0.18;
uniform float sway_speed = 1.6;
uniform float height_ref = 3.0;    // local height that maps to full sway/gradient
uniform float roughness_val = 0.9;
// Grass sets this to 1: flat blades are lit as if facing the sky so a field
// reads bright and lush instead of black side-on. Trees leave it 0.
uniform float sky_lit = 0.0;

varying float grad;
varying float inst_rand;   // 0..1 per-instance, for color/height variety

void vertex() {
	float w = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	grad = w;
	// Per-instance phase + random from world translation (works for MultiMesh).
	float phase = MODEL_MATRIX[3].x * 0.6 + MODEL_MATRIX[3].z * 0.4;
	inst_rand = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	float t = TIME * sway_speed + phase;
	VERTEX.x += sin(t) * sway_strength * w;
	VERTEX.z += cos(t * 0.8) * sway_strength * w * 0.7;
}

void fragment() {
	// Vertex colour tints per-leaf/needle variety (autumn, dry patches); meshes
	// with no COLOR attribute get white (1,1,1) so this is a no-op for them.
	ALBEDO = mix(color_bottom, color_top, grad) * COLOR.rgb;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.1;
	if (sky_lit > 0.5) {
		// Per-clump variety: some clumps drier/tan, and overall brightness varies
		// so the field doesn't read as one flat sheet of green.
		vec3 dry = vec3(0.44, 0.40, 0.17);
		ALBEDO = mix(ALBEDO, dry, smoothstep(0.62, 1.0, inst_rand) * 0.55);
		ALBEDO *= mix(0.82, 1.12, fract(inst_rand * 7.13));
		// Bend the shading normal toward world-up so blades catch the sun.
		vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, up_view, 0.85));
		EMISSION = ALBEDO * 0.05;   // lift shadowed blades slightly
	}
}
