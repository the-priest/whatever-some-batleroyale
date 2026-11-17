shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Gem crystals: a deep coloured core that brightens toward the faceted edges
// and the tip, with a slow light moving up through it.

uniform vec3 core : source_color = vec3(0.12, 0.62, 0.95);
uniform vec3 glow : source_color = vec3(0.08, 0.55, 1.0);
uniform float energy = 1.25;

varying vec3 w_pos;
varying float local_y;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_y = VERTEX.y;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Edges and grazing faces catch the light; faces turned to you look in.
	float edge = pow(1.0 - facing, 2.2);
	float pulse = 0.5 + 0.5 * sin(w_pos.y * 1.6 - TIME * 1.2 + w_pos.x * 0.7);
	vec3 deep = core * 0.35;
	ALBEDO = mix(deep, core * 1.15, edge * 0.8 + 0.15);
	METALLIC = 0.1;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	RIM = 0.6;
	RIM_TINT = 0.6;
	float tip = smoothstep(0.2, 1.0, clamp(local_y, 0.0, 1.0));
	EMISSION = glow * energy * (0.35 + edge * 0.9 + pulse * 0.25 + tip * 0.3);
}
