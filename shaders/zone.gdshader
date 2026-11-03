shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.34, 0.62, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.26;
uniform float scan_speed = 2.2;

varying float v_h;
varying vec3 v_world;

void vertex() {
	v_h = UV.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = clamp(v_h, 0.0, 1.0);
	float base = smoothstep(0.0, 0.10, h) * (1.0 - smoothstep(0.72, 1.0, h) * 0.65);
	float scan = 0.68 + 0.32 * sin(v_world.y * 0.42 + TIME * scan_speed);
	float grid = 0.85 + 0.15 * sin(atan(v_world.z, v_world.x) * 420.0);
	ALBEDO = tint.rgb * (0.75 + scan * 0.55);
	ALPHA = opacity * base * scan * grid;
}
