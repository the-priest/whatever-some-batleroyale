shader_type spatial;
// depth_draw_never: a huge transparent plane must never erase a ground pixel.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Two scrolling noise normal maps instead of summed sines (which tiled into
// visible stripes from the air), with detail fading out over distance.

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.03, 0.17, 0.24);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.42, 0.46);
uniform vec3 sky_tint : source_color = vec3(0.58, 0.74, 0.90);
uniform float alpha_base = 0.86;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	vec2 uv1 = wpos.xz * 0.018 + vec2(t * 0.010, t * 0.006);
	vec2 uv2 = wpos.xz * 0.047 + vec2(-t * 0.014, t * 0.011);
	vec3 n1 = texture(normal_a, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(normal_b, uv2).xyz * 2.0 - 1.0;
	vec2 slope = (n1.xy * 0.6 + n2.xy * 0.4);
	// Far water flattens into a calm, reflective sheet.
	float detail = 1.0 - smoothstep(60.0, 700.0, dist);
	slope *= 0.35 + 0.65 * detail;
	vec3 n = normalize(vec3(slope.x * 0.55, 1.0, slope.y * 0.55));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float shallow = clamp(0.5 + slope.x * 2.0, 0.0, 1.0) * detail;
	vec3 col = mix(deep_color, shallow_color, shallow * 0.55);
	col = mix(col, sky_tint, fres * 0.5);

	ALBEDO = col;
	ALPHA = clamp(alpha_base + fres * 0.14, 0.0, 1.0);
	ROUGHNESS = mix(0.18, 0.04, 1.0 - detail);
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
