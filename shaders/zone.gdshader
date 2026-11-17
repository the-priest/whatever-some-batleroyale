shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

// Storm wall. Soft rolling noise instead of a fine stripe pattern, which used to
// shimmer (moire) at a distance.

uniform vec4 tint : source_color = vec4(0.52, 0.34, 0.95, 1.0);
uniform vec4 edge : source_color = vec4(0.86, 0.72, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.42;
uniform float radius = 430.0;

varying vec3 v_world;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float around = UV.x * radius * 6.2831;
	vec2 p = vec2(around * 0.025, v_world.y * 0.03);
	float t = TIME * 0.12;
	float n = fbm(p + vec2(t, -t * 1.6));
	n = mix(n, fbm(p * 2.3 - vec2(t * 1.3, t * 0.7)), 0.4);

	// Fade out toward the top so the storm does not read as a hard tube: by
	// world height, all the way to nothing well below the mesh's top edge
	// (a cylinder's side UVs only span 0..0.5, so they cannot do this).
	float h = clamp((v_world.y - 30.0) / 330.0, 0.0, 1.0);
	float vertical = 1.0 - smoothstep(0.0, 1.0, h);
	vertical *= vertical;

	// Do not paint a solid sheet right in front of the camera.
	float d = length(v_world - CAMERA_POSITION_WORLD);
	float near = smoothstep(2.0, 18.0, d);

	vec3 col = mix(tint.rgb, edge.rgb, smoothstep(0.55, 0.85, n));
	ALBEDO = col;
	ALPHA = opacity * vertical * near * (0.45 + 0.75 * n);
}
