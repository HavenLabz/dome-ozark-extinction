shader_type canvas_item;
// Screen-edge damage vignette. `strength` (0..1) is driven by the HUD from low
// health + recent hits; edges redden while the centre stays clear.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.65, 0.02, 0.02, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv) * 1.5;
	float v = smoothstep(0.35, 0.9, d) * strength;
	COLOR = vec4(tint.rgb, v);
}
