shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Near-camera meadow grass. Each tuft takes its colour from the same grass
// texture the terrain uses at its root, so blades melt into the ground, and
// shrinks to nothing towards the edge of the field so there is no border.
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform float fade_end = 40.0;
uniform float wind = 0.09;

varying vec3 root_col;
varying float hfrac;

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(root.xz, CAMERA_POSITION_WORLD.xz);
	float s = 1.0 - smoothstep(fade_end * 0.7, fade_end, d);
	hfrac = UV.y;
	VERTEX.y *= s;
	float ph = TIME * 1.55 + root.x * 0.31 + root.z * 0.23;
	float sway = (sin(ph) * 0.7 + sin(ph * 2.3 + 1.7) * 0.3) * wind * UV.y * UV.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
	NORMAL = vec3(0.0, 1.0, 0.0);
	vec3 g = textureLod(tex_grass, root.xz * 0.135, 5.0).rgb;
	root_col = g * COLOR.rgb;
}

void fragment() {
	vec3 base = root_col * 0.7;
	vec3 tip = root_col * 1.3 + vec3(0.035, 0.045, 0.0);
	ALBEDO = mix(base, tip, hfrac);
	ROUGHNESS = 0.94;
	BACKLIGHT = vec3(0.22, 0.32, 0.08) * hfrac;
}
