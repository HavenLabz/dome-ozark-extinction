shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Stylized Ozark water: gentle vertex waves, scrolling ripple normals,
// depth-tinted color, and a fresnel rim. Transparent. No texture assets.

uniform vec3 shallow_color : source_color = vec3(0.25, 0.45, 0.42);
uniform vec3 deep_color : source_color = vec3(0.06, 0.16, 0.24);
uniform float wave_height = 0.12;
uniform float wave_speed = 0.6;
uniform float ripple_scale = 0.7;

varying vec3 w_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			   mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float wave = sin(w_pos.x * 0.3 + t) * cos(w_pos.z * 0.25 + t * 1.3);
	VERTEX.y += wave * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	// Two scrolling ripple layers perturb the normal.
	float n1 = noise(w_pos.xz * ripple_scale + vec2(t * 0.5, t * 0.3));
	float n2 = noise(w_pos.xz * ripple_scale * 2.3 - vec2(t * 0.4, t * 0.6));
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.3, 1.0, (n2 - 0.5) * 0.3));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
	vec3 col = mix(deep_color, shallow_color, fres);

	ALBEDO = col;
	METALLIC = 0.15;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	ALPHA = mix(0.72, 0.95, fres);
	EMISSION = shallow_color * fres * 0.15;
}
