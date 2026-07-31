shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform float strike_angle = 0.436332313;
uniform float sprite_height = 0.72;

void vertex() {
	vec2 anchored = VERTEX.xy + vec2(0.0, sprite_height * 0.5);
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
