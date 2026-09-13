shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform bool textured = false;
uniform bool foliage = false;

void vertex() {
	float weight = pow(clamp(VERTEX.y / 6.0, 0.0, 1.0), 1.7);
	float phase = MODEL_MATRIX[3].x * 0.63 + MODEL_MATRIX[3].z * 0.41;
	float strength = foliage ? 0.028 : 0.014;
	VERTEX.x += sin(TIME * 1.25 + phase + VERTEX.y * 0.45) * strength * weight;
	VERTEX.z += sin(TIME * 1.63 + phase + VERTEX.x) * strength * weight * 0.45;
}

void fragment() {
	ALBEDO = tint.rgb * (textured ? texture(albedo_map, UV).rgb : vec3(1.0));
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
