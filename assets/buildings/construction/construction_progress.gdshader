shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 0.95, 0.78, 0.34);
uniform vec4 fill_color : source_color = vec4(1.0, 0.68, 0.20, 0.56);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float radius = length(centered);
	float ring = 1.0 - smoothstep(0.455, 0.49, radius);
	ring *= smoothstep(0.405, 0.445, radius);
	float inside = 1.0 - smoothstep(0.40, 0.43, radius);
	float clockwise = mod(atan(centered.x, -centered.y) / 6.28318530718 + 1.0, 1.0);
	float sector = (1.0 - step(progress, clockwise)) * inside * step(0.0001, progress);
	vec4 color = ring_color * ring + fill_color * sector;
	ALBEDO = color.rgb;
	ALPHA = clamp(color.a, 0.0, 1.0);
}
