shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_macro : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D road_mask : filter_linear, repeat_disable;
uniform float map_half = 1200.0;

varying vec4 vw;
varying vec3 wpos;
varying vec3 wnrm;
// How wooded this ground is (0..1): far away, where the trees themselves are
// culled, the ground takes on the canopy's colour so forests still read.
varying float canopy;
uniform float canopy_near = 520.0;
uniform float canopy_far = 760.0;

void vertex() {
	vw = COLOR;
	canopy = UV2.x;
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

	// Dirt roads: packed earth with paler wheel ruts.
	float road = texture(road_mask, (wpos.xz + vec2(map_half)) / (2.0 * map_half)).r;
	if (road > 0.001) {
		vec3 track = dirt * vec3(1.08, 1.0, 0.9) * (0.9 + macro * 0.15);
		float rut = smoothstep(0.55, 0.75, road) * (1.0 - smoothstep(0.8, 0.95, road));
		track *= 1.0 - rut * 0.18;
		col = mix(col, track, smoothstep(0.0, 0.5, road) * 0.92);
	}
	float far_k = smoothstep(canopy_near, canopy_far, length(wpos - CAMERA_POSITION_WORLD));
	if (far_k > 0.0 && canopy > 0.0) {
		vec3 leaf = vec3(0.13, 0.27, 0.11) * (0.8 + macro * 0.4);
		col = mix(col, leaf, clamp(canopy, 0.0, 1.0) * far_k * 0.85);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.82, clamp(vw.b, 0.0, 1.0));
	SPECULAR = 0.28;
	AO = mix(1.0, 0.86, clamp(vw.b, 0.0, 1.0));
}
