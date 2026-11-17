shader_type canvas_item;

// The island as a printed map: bright cartoon terrain shaded straight from the
// height data, so it stays sharp at any zoom (minimap, full map, lobby).

// R = ground height in metres, G = water depth there (above 0 = under water).
uniform sampler2D data_tex : filter_linear, repeat_disable;
// Tree cover, one blob per planted tree.
uniform sampler2D canopy_tex : filter_linear_mipmap, repeat_disable;

uniform vec2 view_origin = vec2(-1200.0, -1200.0);
uniform vec2 view_span = vec2(2400.0, 2400.0);
uniform float px_per_m = 0.25;
uniform float half_size = 1200.0;
uniform float cell = 6.0;
uniform float data_res = 401.0;
uniform float grid_alpha = 1.0;

const vec3 SEA_DEEP = vec3(0.090, 0.275, 0.420);
const vec3 SEA_MID = vec3(0.150, 0.420, 0.560);
const vec3 SEA_SHALLOW = vec3(0.330, 0.640, 0.700);
const vec3 FOAM = vec3(0.840, 0.950, 0.940);
const vec3 SAND = vec3(0.905, 0.835, 0.620);
const vec3 GRASS_LOW = vec3(0.500, 0.705, 0.320);
const vec3 GRASS_MID = vec3(0.590, 0.745, 0.370);
const vec3 GRASS_HIGH = vec3(0.720, 0.770, 0.470);
const vec3 PEAK = vec3(0.820, 0.800, 0.640);
const vec3 ROCK = vec3(0.610, 0.590, 0.550);
const vec3 WOOD = vec3(0.215, 0.470, 0.250);
const vec3 WOOD_DARK = vec3(0.140, 0.340, 0.200);
const vec3 WOOD_LIT = vec3(0.330, 0.590, 0.300);
const vec3 INK = vec3(0.230, 0.170, 0.090);

vec2 data_uv(vec2 w) {
	return ((w + half_size) / cell + 0.5) / data_res;
}

vec4 cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

// Smooth (bicubic) height so the contour lines curve instead of zig-zagging.
float height_at(vec2 w) {
	vec2 uv = data_uv(w) * data_res - 0.5;
	vec2 f = fract(uv);
	uv -= f;
	vec4 xc = cubic(f.x);
	vec4 yc = cubic(f.y);
	vec4 c = uv.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 o = (c + vec4(xc.yw, yc.yw) / s) / data_res;
	float s0 = texture(data_tex, o.xz).r;
	float s1 = texture(data_tex, o.yz).r;
	float s2 = texture(data_tex, o.xw).r;
	float s3 = texture(data_tex, o.yw).r;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

float canopy_at(vec2 w) {
	return texture(canopy_tex, (w + half_size) / (half_size * 2.0)).r;
}

void fragment() {
	vec2 w = view_origin + UV * view_span;
	float m_per_px = 1.0 / max(px_per_m, 0.0001);

	float h = height_at(w);
	float depth = texture(data_tex, data_uv(w)).g;
	float e = cell;
	float hx = height_at(w + vec2(e, 0.0)) - height_at(w - vec2(e, 0.0));
	float hz = height_at(w + vec2(0.0, e)) - height_at(w - vec2(0.0, e));
	vec3 nrm = normalize(vec3(-hx, 2.0 * e, -hz));
	float slope = 1.0 - nrm.y;
	// Sun from the north-west, as on any printed map.
	float lit = dot(nrm, normalize(vec3(-0.55, 0.62, -0.55)));

	// Land.
	vec3 land = mix(GRASS_LOW, GRASS_MID, smoothstep(2.0, 22.0, h));
	land = mix(land, GRASS_HIGH, smoothstep(26.0, 62.0, h));
	land = mix(land, PEAK, smoothstep(70.0, 112.0, h));
	land = mix(land, ROCK, smoothstep(0.20, 0.36, slope));
	land = mix(SAND, land, smoothstep(0.5, 1.9, -depth));
	land *= 0.74 + 0.52 * smoothstep(0.30, 0.95, lit);

	// Height lines: every 10 m, heavier every 50 m.
	float hw = max(fwidth(h), 0.0001);
	float c10 = abs(fract(h / 10.0 + 0.5) - 0.5) * 10.0 / hw;
	float c50 = abs(fract(h / 50.0 + 0.5) - 0.5) * 50.0 / hw;
	float on_land = smoothstep(1.2, 2.6, -depth) * smoothstep(3.0, 5.0, h);
	// Too crowded to read on cliffs and from far out: let them fade.
	float crowd = smoothstep(9.0, 3.5, hw);
	float line10 = (1.0 - smoothstep(0.35, 1.15, c10)) * 0.17 * crowd * smoothstep(0.16, 0.42, px_per_m);
	float line50 = (1.0 - smoothstep(0.55, 1.45, c50)) * 0.30 * smoothstep(40.0, 12.0, hw);
	land = mix(land, INK, max(line10, line50) * on_land);

	// Woods: a blob per tree up close, a soft green wash from far out.
	float near = smoothstep(0.22, 0.60, px_per_m);
	float cv = canopy_at(w);
	float lo = mix(0.03, 0.34, near);
	float hi = mix(0.50, 0.48, near);
	float wood = smoothstep(lo, hi, cv);
	vec2 sun = normalize(vec2(-1.0, -1.0));
	float off = max(1.6, 1.3 * m_per_px);
	float toward = canopy_at(w + sun * off);
	float away = canopy_at(w - sun * off);
	// Shadow each crown throws on the grass beside it.
	float shadow = smoothstep(lo, hi, canopy_at(w + sun * off * 2.2)) * (1.0 - wood) * near;
	land *= 1.0 - shadow * 0.20;
	vec3 leaf = mix(WOOD, WOOD_LIT, clamp((away - toward) * 2.2 * near + 0.18, 0.0, 1.0));
	leaf = mix(leaf, WOOD_DARK, clamp((toward - away) * 2.4 * near, 0.0, 1.0));
	// Darker rim where a crown ends.
	leaf = mix(WOOD_DARK, leaf, mix(1.0, smoothstep(hi, hi + 0.22, cv), near * 0.75));
	leaf *= 0.84 + 0.30 * smoothstep(0.30, 0.95, lit);
	land = mix(land, leaf, wood * mix(0.82, 1.0, near) * smoothstep(0.6, 1.6, -depth));

	// Water: banded depths, a foam line on every shore.
	float d = max(depth, 0.0);
	vec3 sea = mix(SEA_SHALLOW, SEA_MID, smoothstep(0.3, 4.5, d));
	sea = mix(sea, SEA_DEEP, smoothstep(4.5, 16.0, d));
	float band = abs(fract(d / 6.0 + 0.5) - 0.5) * 6.0 / max(fwidth(d), 0.0001);
	sea = mix(sea, sea * 1.10, (1.0 - smoothstep(0.4, 1.3, band)) * 0.35 * smoothstep(1.0, 3.0, d) * smoothstep(40.0, 16.0, d));
	float dw = max(fwidth(depth), 0.0001);
	float shore = abs(depth - 0.12) / dw;
	sea = mix(sea, FOAM, (1.0 - smoothstep(0.7, 1.9, shore)) * 0.80);

	float wet = smoothstep(-0.5, 0.5, depth / dw);
	vec3 col = mix(land, sea, wet);

	// Off the edge of the world: open sea.
	vec2 out_m = max(abs(w) - half_size, vec2(0.0));
	float outside = clamp(max(out_m.x, out_m.y) * px_per_m, 0.0, 1.0);
	col = mix(col, SEA_DEEP * 0.80, outside);

	// World-aligned grid: 300 m squares (the A-H / 1-8 references), 100 m
	// squares once you are close enough to use them.
	vec2 g3 = abs(fract(w / 300.0 + 0.5) - 0.5) * 300.0 * px_per_m;
	float l3 = 1.0 - smoothstep(0.35, 1.25, min(g3.x, g3.y));
	vec2 g1 = abs(fract(w / 100.0 + 0.5) - 0.5) * 100.0 * px_per_m;
	float l1 = (1.0 - smoothstep(0.30, 1.10, min(g1.x, g1.y))) * smoothstep(0.45, 0.95, px_per_m);
	float grid = max(l3 * 0.20, l1 * 0.09) * grid_alpha * (1.0 - outside);
	col = mix(col, vec3(1.0), grid);

	COLOR = vec4(col, 1.0);
}
