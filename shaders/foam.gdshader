shader_type spatial;
// Churned white water on the plunge pool, fading out from the impact point.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D streaks : filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float ang = atan(c.y, c.x);
	float n = texture(streaks, vec2(ang * 0.6, r * 1.2 - TIME * 0.35)).r;
	float n2 = texture(streaks, vec2(UV.x * 2.0 + TIME * 0.05, UV.y * 2.0 - TIME * 0.07)).r;
	float a = (1.0 - smoothstep(0.25, 1.0, r)) * smoothstep(0.3, 0.7, n * 0.6 + n2 * 0.5);
	ALBEDO = vec3(0.93, 0.96, 0.98);
	ALPHA = a * 0.85;
}
