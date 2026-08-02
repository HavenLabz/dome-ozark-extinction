shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// PBR-ish river water: vertex waves, animated ripple normals, screen-space
// refraction (you see the distorted bed through it), depth-based colour (darker
// where deeper), a soft shoreline that fades at the waterline, and animated
// foam where the water meets land. No texture assets — all procedural.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 shallow_color : source_color = vec3(0.22, 0.42, 0.44);
uniform vec3 deep_color : source_color = vec3(0.04, 0.13, 0.22);
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 0.97);
uniform float wave_height = 0.12;
uniform float wave_speed = 0.6;
uniform float ripple_scale = 0.7;
uniform float refraction = 0.035;
uniform float depth_fade = 3.2;      // world units to reach full deep colour
uniform float foam_width = 1.1;      // shore foam band (world units of depth)

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
	// Two scrolling ripple layers perturb the surface normal.
	float n1 = noise(w_pos.xz * ripple_scale + vec2(t * 0.5, t * 0.3));
	float n2 = noise(w_pos.xz * ripple_scale * 2.3 - vec2(t * 0.4, t * 0.6));
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.35, 1.0, (n2 - 0.5) * 0.35));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	// Reconstruct how much water sits between the surface and the bed.
	float raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float water_depth = max(0.0, VERTEX.z - view.z);   // >0 where bed is behind the surface

	float dfade = clamp(water_depth / depth_fade, 0.0, 1.0);
	vec3 water_col = mix(shallow_color, deep_color, dfade);

	// Refraction: sample the scene behind, distorted by the ripple normal.
	vec2 ruv = SCREEN_UV + nrm.xz * refraction * (0.3 + dfade);
	vec3 refr = texture(screen_tex, ruv).rgb;
	vec3 col = mix(refr, water_col, clamp(dfade + 0.4, 0.0, 1.0));

	// Animated shoreline foam.
	float foam = 1.0 - smoothstep(0.0, foam_width, water_depth);
	foam *= smoothstep(0.35, 0.75, noise(w_pos.xz * 3.0 + vec2(t * 0.8, -t * 0.6)) + 0.25);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.85);

	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 4.0);
	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.05, 0.35, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.65;
	EMISSION = foam_color * foam * 0.12 + shallow_color * fres * 0.08;
	// Fade out exactly at the waterline so there's no hard shoreline seam.
	ALPHA = clamp(smoothstep(0.0, 0.12, water_depth) + foam, 0.0, 1.0);
}
