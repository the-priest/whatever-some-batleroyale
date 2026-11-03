shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wind_strength = 0.2;
uniform float alpha_cut = 0.34;
uniform float sway_height = 1.8;

varying vec3 wpos;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = world;
	float phase = world.x * 0.33 + world.z * 0.21;
	float sway = sin(TIME * 1.45 + phase) + 0.45 * sin(TIME * 2.83 + phase * 1.7);
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	VERTEX.x += sway * wind_strength * h;
	VERTEX.z += cos(TIME * 1.17 + phase * 0.9) * wind_strength * 0.55 * h;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.92;
	SPECULAR = 0.18;
	BACKLIGHT = tex.rgb * vec3(0.22, 0.28, 0.14);
}
