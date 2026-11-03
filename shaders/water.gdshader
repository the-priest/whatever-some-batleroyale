shader_type spatial;
// depth_draw_never: a 2.6 km transparent plane must never be able to erase or
// occlude a ground pixel. It blends over the sea and nothing else.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.045, 0.16, 0.20);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.42, 0.44);
uniform vec3 sky_tint : source_color = vec3(0.62, 0.78, 0.90);
uniform float wave_scale = 0.055;
uniform float wave_speed = 0.5;
uniform float alpha_base = 0.80;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = wpos.xz * wave_scale;
	float w = sin(p.x * 1.7 + t) * cos(p.y * 1.31 - t * 0.83);
	w += 0.55 * sin((p.x + p.y) * 3.1 + t * 1.9);
	w += 0.28 * sin((p.x - p.y) * 6.7 - t * 2.7);
	w *= 0.34;

	vec3 n = normalize(vec3(w * 0.09, 1.0, cos(p.x * 2.1 - t * 0.61) * 0.07));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	vec3 col = mix(deep_color, shallow_color, clamp(w * 1.4 + 0.5, 0.0, 1.0));
	col = mix(col, sky_tint, fres * 0.65);

	ALBEDO = col;
	ALPHA = clamp(alpha_base + fres * 0.18, 0.0, 1.0);
	ROUGHNESS = 0.06;
	SPECULAR = 0.62;
	METALLIC = 0.0;
}
