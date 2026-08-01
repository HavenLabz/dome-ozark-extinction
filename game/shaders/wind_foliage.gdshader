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

void vertex() {
	float w = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	grad = w;
	// Per-instance phase from world translation (works for MultiMesh too).
	float phase = MODEL_MATRIX[3].x * 0.6 + MODEL_MATRIX[3].z * 0.4;
	float t = TIME * sway_speed + phase;
	VERTEX.x += sin(t) * sway_strength * w;
	VERTEX.z += cos(t * 0.8) * sway_strength * w * 0.7;
}

void fragment() {
	ALBEDO = mix(color_bottom, color_top, grad);
	ROUGHNESS = roughness_val;
	SPECULAR = 0.1;
	if (sky_lit > 0.5) {
		// Bend the shading normal toward world-up so blades catch the sun.
		vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, up_view, 0.85));
		EMISSION = ALBEDO * 0.06;   // lift shadowed blades slightly
	}
}
