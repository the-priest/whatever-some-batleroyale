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
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform bool shore = true;

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

	float alpha_base_mod = 0.0;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float shallow = clamp(0.5 + slope.x * 2.0, 0.0, 1.0) * detail;
	vec3 col = mix(deep_color, shallow_color, shallow * 0.55);
	col = mix(col, sky_tint, fres * 0.5);

	// Shore: how much water lies between this surface and the ground under
	// it, from the depth buffer. Shallows go clear turquoise, the edge itself
	// fades in, and foam laps the beach in bands that run up and back.
	float edge_fade = 1.0;
	if (shore) {
		float d = texture(depth_tex, SCREEN_UV).r;
		vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		vec4 vp = INV_PROJECTION_MATRIX * ndc;
		vp.xyz /= vp.w;
		float ground_dist = length(vp.xyz);
		float surf_dist = length(VERTEX);
		// Water thickness along the view ray, turned into a vertical depth.
		float thick = max(0.0, ground_dist - surf_dist) * clamp(abs(dot(normalize(VERTEX), (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)), 0.08, 1.0);
		float near_k = 1.0 - smoothstep(90.0, 220.0, dist);
		float shal = 1.0 - smoothstep(0.0, 1.0, thick);
		col = mix(col, vec3(0.2, 0.62, 0.6), shal * 0.7 * near_k);
		float wave = sin(thick * 9.0 - t * 1.6 + (wpos.x + wpos.z) * 0.05) * 0.5 + 0.5;
		float band = (1.0 - smoothstep(0.03, 0.6, thick)) * (0.3 + 0.7 * wave);
		float noise_n = texture(normal_b, wpos.xz * 0.11 + vec2(t * 0.02, 0.0)).x;
		band *= smoothstep(0.25, 0.6, noise_n + band * 0.5);
		float edge = 1.0 - smoothstep(0.0, 0.08, thick);
		float foam = clamp(max(band, edge * 0.9), 0.0, 1.0) * near_k;
		col = mix(col, foam_color, foam);
		ROUGHNESS = mix(0.18, 0.7, foam);
		edge_fade = mix(1.0, smoothstep(0.0, 0.02, thick), near_k);
		alpha_base_mod = foam;
	}
	ALBEDO = col;
	// Far water (and everything seen from the plane) is opaque, so the edge of
	// the modelled sea floor never shows through.
	float far_opaque = smoothstep(120.0, 420.0, dist);
	ALPHA = max(clamp(mix(alpha_base + fres * 0.14 + alpha_base_mod * 0.3, 1.0, far_opaque), 0.0, 1.0) * edge_fade, alpha_base_mod * 0.85);
	if (!shore) {
		ROUGHNESS = mix(0.18, 0.04, 1.0 - detail);
	}
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
