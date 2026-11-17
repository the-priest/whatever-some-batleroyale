shader_type canvas_item;
// Colour-blind filter (daltonisation): works out what a colour looks like
// to someone with the given deficiency, and shifts the difference into
// colours they can tell apart. 1 protanopia, 2 deuteranopia, 3 tritanopia.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform int mode = 0;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float L = 17.8824 * c.r + 43.5161 * c.g + 4.11935 * c.b;
	float M = 3.45565 * c.r + 27.1554 * c.g + 3.86714 * c.b;
	float S = 0.0299566 * c.r + 0.184309 * c.g + 1.46709 * c.b;
	float l = L;
	float m = M;
	float s = S;
	if (mode == 1) {
		l = 2.02344 * M - 2.52581 * S;
	} else if (mode == 2) {
		m = 0.494207 * L + 1.24827 * S;
	} else if (mode == 3) {
		s = -0.395913 * L + 0.801109 * M;
	}
	vec3 sim = vec3(
		0.0809444479 * l - 0.130504409 * m + 0.116721066 * s,
		-0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s,
		-0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s);
	vec3 err = c - sim;
	vec3 fix = vec3(0.0, err.r * 0.7 + err.g, err.r * 0.7 + err.b);
	COLOR = vec4(clamp(c + fix, 0.0, 1.0), 1.0);
}
