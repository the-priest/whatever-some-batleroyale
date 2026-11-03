shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_macro : source_color, filter_linear_mipmap, repeat_enable;

varying vec4 vw;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	vw = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec2 uv = wpos.xz * 0.135;
	vec2 uv2 = wpos.xz * 0.031;
	vec2 uv3 = wpos.xz * 0.021;

	vec3 grass = texture(tex_grass, uv).rgb;
	vec3 grass2 = texture(tex_grass, uv3 * 1.7 + vec2(0.37, 0.11)).rgb;
	grass = mix(grass, grass2, 0.45);

	vec3 dirt = texture(tex_dirt, uv * 0.9).rgb;
	vec3 sand = texture(tex_sand, uv * 0.75 + vec2(0.13, 0.4)).rgb;

	// Triplanar rock so cliff faces do not stretch.
	vec3 rn = abs(n);
	rn /= max(0.001, rn.x + rn.y + rn.z);
	vec3 rock = texture(tex_rock, wpos.zy * 0.11).rgb * rn.x;
	rock += texture(tex_rock, wpos.xz * 0.11).rgb * rn.y;
	rock += texture(tex_rock, wpos.xy * 0.11).rgb * rn.z;

	float macro = texture(tex_macro, uv2).r;
	float macro2 = texture(tex_macro, uv3 * 2.3 + vec2(0.5)).r;

	vec3 col = grass * vw.r + sand * vw.g + rock * vw.b + dirt * vw.a;
	col *= 0.86 + macro * 0.24;
	col *= 0.94 + macro2 * 0.12;

	// A touch of cool bounce in the low ground, warm sun on the tops.
	float h = clamp((wpos.y - 1.0) / 45.0, 0.0, 1.0);
	col = mix(col * vec3(0.94, 0.98, 1.04), col * vec3(1.04, 1.01, 0.95), h);

	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.82, clamp(vw.b, 0.0, 1.0));
	SPECULAR = 0.28;
	AO = mix(1.0, 0.86, clamp(vw.b, 0.0, 1.0));
}
