shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Wheat stalks: golden gradient from the stem to the ear, swaying in rows.
uniform vec3 base_col : source_color = vec3(0.5, 0.42, 0.16);
uniform vec3 tip_col : source_color = vec3(0.95, 0.8, 0.4);
uniform float wind = 0.12;

varying float hfrac;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	hfrac = UV.y;
	float ph = TIME * 1.3 + root.x * 0.22 + root.z * 0.17;
	float sway = (sin(ph) * 0.75 + sin(ph * 2.1 + 0.8) * 0.25) * wind * UV.y * UV.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.4;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(base_col, tip_col, smoothstep(0.0, 1.0, hfrac)) * COLOR.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.3, 0.25, 0.08) * hfrac;
}
