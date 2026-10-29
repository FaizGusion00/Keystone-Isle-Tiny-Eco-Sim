shader_type canvas_item;
// Sea and lake surface for the whole island in one quad. A tiny per-tile data texture
// (R = land, G = mud, B = depth) is sampled with bilinear filtering, so shorelines, foam and
// muddy plumes are smooth even though the simulation is a 32x32 grid.
uniform sampler2D data : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(32.0, 32.0);
uniform float motion = 1.0;
uniform vec4 deep_col : source_color = vec4(0.17, 0.38, 0.50, 1.0);
uniform vec4 mid_col : source_color = vec4(0.27, 0.55, 0.64, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.50, 0.76, 0.76, 1.0);
uniform vec4 mud_col : source_color = vec4(0.58, 0.47, 0.32, 1.0);
uniform vec4 foam_col : source_color = vec4(0.93, 0.96, 0.94, 1.0);
uniform float overlay_mud = 0.0;
varying vec2 local_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() { local_pos = VERTEX; }

void fragment() {
	float fx = local_pos.x / 32.0;
	float fy = local_pos.y / 16.0;
	vec2 t = vec2((fy + fx) * 0.5, (fy - fx) * 0.5);   // tile coords, centres on integers
	vec2 uv = (t + 0.5) / map_size;
	vec4 d = texture(data, clamp(uv, vec2(0.0), vec2(1.0)));
	float outside = max(max(-uv.x, uv.x - 1.0), max(-uv.y, uv.y - 1.0));
	if (outside > 0.0) { d = vec4(0.0, 0.0, 1.0, 1.0); }
	float land = d.r;
	float depth = d.b;
	float tm = TIME * motion;
	float n = noise(t * 0.9 + vec2(tm * 0.12, tm * 0.08)) * 0.6 + noise(t * 2.2 - vec2(tm * 0.15, -tm * 0.1)) * 0.4;
	vec3 col = mix(shallow_col.rgb, mid_col.rgb, smoothstep(0.0, 0.55, depth));
	col = mix(col, deep_col.rgb, smoothstep(0.55, 1.0, depth));
	col += (n - 0.5) * 0.06;
	// muddy plume
	float mud = clamp(d.g * (1.0 + overlay_mud * 1.5), 0.0, 0.9);
	col = mix(col, mud_col.rgb, mud * (0.75 + 0.25 * n));
	// shore foam: animated bands where the land field fades out
	float shore = smoothstep(0.08, 0.42, land);
	float bands = 0.5 + 0.5 * sin(land * 26.0 - tm * 1.6 + n * 4.0);
	float foam = shore * smoothstep(0.55, 0.9, bands) * 0.55 + smoothstep(0.32, 0.47, land) * 0.5;
	col = mix(col, foam_col.rgb, clamp(foam, 0.0, 0.85));
	// sparkle
	float sp = smoothstep(0.80, 0.97, noise(t * vec2(3.0, 6.0) + vec2(tm * 0.35, tm * 0.2))) * (1.0 - shore) * 0.10;
	col += sp;
	// soft vignette into the far ocean
	float fade = smoothstep(0.0, 0.35, outside);
	col = mix(col, deep_col.rgb * 0.82, fade);
	COLOR = vec4(col, 1.0);
}
