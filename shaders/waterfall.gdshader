shader_type spatial;
// Falling water: streaks scrolling down the sheet, whiter where it breaks up
// toward the edges and the bottom.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D streaks : filter_linear_mipmap, repeat_enable;
uniform float speed = 1.4;
uniform vec3 water_color : source_color = vec3(0.55, 0.72, 0.78);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float opacity = 0.9;
uniform float foam_bias = 0.0;

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float a = texture(streaks, vec2(uv.x * 1.6, uv.y * 0.18 - t * 0.55)).r;
	float b = texture(streaks, vec2(uv.x * 3.1 + 0.37, uv.y * 0.32 - t * 0.9)).r;
	float n = a * 0.6 + b * 0.4;
	float edge = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	float foam = clamp(smoothstep(0.42, 0.75, n) + foam_bias + (1.0 - edge) * 0.4, 0.0, 1.0);
	ALBEDO = mix(water_color, foam_color, foam);
	EMISSION = foam_color * foam * 0.12;
	ROUGHNESS = mix(0.1, 0.7, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(opacity * edge * (0.55 + n * 0.7), 0.0, 1.0);
}
