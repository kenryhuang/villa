shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform float strike_angle = 0.436332313;
uniform float sprite_height = 0.72;
uniform vec2 pivot_uv = vec2(0.5, 1.0);

void vertex() {
	vec2 pivot_local = vec2(
		(pivot_uv.x - 0.5) * sprite_height,
		(0.5 - pivot_uv.y) * sprite_height
	);
	vec2 anchored = VERTEX.xy - pivot_local;
	float cosine = cos(strike_angle);
	float sine = sin(strike_angle);
	VERTEX.xy = vec2(
		anchored.x * cosine - anchored.y * sine,
		anchored.x * sine + anchored.y * cosine
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec4 painted = texture(albedo_texture, UV) * COLOR;
	ALBEDO = painted.rgb;
	ALPHA = painted.a;
}
