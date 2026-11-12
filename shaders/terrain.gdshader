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
// Rain: 0 dry .. 1 soaked. Soil darkens, stone and roads go glossy, and
// water pools in the flat ruts and hollows.
uniform float wetness = 0.0;
// Tree cover baked from the trees actually planted (world_builder minimap).
uniform sampler2D canopy_map : filter_linear_mipmap, repeat_disable;
uniform bool has_canopy_map = false;
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
	// Under the trees: leaf litter, needles and moss in patches instead of
	// meadow grass, a little darker where the canopy closes over.
	float under = 0.0;
	if (has_canopy_map) {
		under = textureLod(canopy_map, (wpos.xz + vec2(map_half)) / (2.0 * map_half), 1.0).r;
	}
	float cov = clamp(under * 1.3, 0.0, 1.0) * clamp(vw.r * 1.4, 0.0, 1.0) * (1.0 - clamp(road * 2.0, 0.0, 1.0));
	if (cov > 0.01) {
		// Fine litter noise from the grass texture's own detail, so it is
		// not one flat brown.
		float fleck = dot(texture(tex_grass, uv * 2.3).rgb, vec3(0.33));
		// Patches of needles and dead leaves through dark mossy grass.
		float patch = smoothstep(0.42, 0.62, macro2 * 0.55 + macro * 0.55 + (fleck - 0.4) * 0.6);
		vec3 litter = mix(vec3(0.085, 0.06, 0.032), vec3(0.16, 0.11, 0.055), fleck) * (0.85 + macro * 0.3);
		vec3 moss = grass * vec3(0.5, 0.62, 0.36);
		vec3 floor_c = mix(moss, litter, patch);
		col = mix(col, floor_c, smoothstep(0.15, 0.7, cov) * 0.8);
	}
	float far_k = smoothstep(canopy_near, canopy_far, length(wpos - CAMERA_POSITION_WORLD));
	if (far_k > 0.0 && canopy > 0.0) {
		vec3 leaf = vec3(0.13, 0.27, 0.11) * (0.8 + macro * 0.4);
		col = mix(col, leaf, clamp(canopy, 0.0, 1.0) * far_k * 0.85);
	}
	float rough = mix(0.96, 0.82, clamp(vw.b, 0.0, 1.0));
	float spec = 0.28;
	if (wetness > 0.0) {
		float bare = clamp(vw.a + vw.g + vw.b + road, 0.0, 1.0);
		col *= mix(1.0, mix(0.82, 0.62, bare), wetness);
		rough = mix(rough, mix(0.7, 0.32, bare), wetness);
		// Puddles: only where it is flat, in the low spots of the noise.
		float flat_k = smoothstep(0.93, 0.985, n.y);
		float hollow = smoothstep(0.58, 0.66, 1.0 - macro * 0.7 - macro2 * 0.5 + (road > 0.5 ? 0.1 : 0.0));
		float pool = flat_k * hollow * wetness * clamp(bare + 0.3, 0.0, 1.0);
		col = mix(col, col * 0.45 + vec3(0.015, 0.02, 0.025), pool);
		rough = mix(rough, 0.04, pool);
		spec = mix(spec, 0.6, pool);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	AO = mix(1.0, 0.86, clamp(vw.b, 0.0, 1.0));
}
