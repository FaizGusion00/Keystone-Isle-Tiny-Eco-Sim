shader_type canvas_item;
// Screen-space light grade over the world (under the HUD): a warm low sun from the upper left
// and a cool, soft falloff into the lower-right corner. Colour and strength come per season.
uniform vec4 warm : source_color = vec4(1.0, 0.86, 0.6, 0.12);
uniform vec4 cool : source_color = vec4(0.08, 0.14, 0.2, 0.2);

void fragment() {
	vec2 uv = SCREEN_UV;
	float sun = 1.0 - smoothstep(0.0, 1.05, length(uv * vec2(1.0, 1.25)));
	float shade = smoothstep(0.55, 1.2, length((uv - vec2(0.42, 0.4)) * vec2(1.25, 1.4)));
	float g = sun * warm.a;
	float v = shade * cool.a;
	float a = max(g, v);
	vec3 col = (warm.rgb * g + cool.rgb * v) / max(g + v, 1e-4);
	COLOR = vec4(col, a);
}
