shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform float wind_strength = 0.04;
uniform float tree_height = 5.9;
uniform bool foliage = true;

vec3 linear_to_srgb(vec3 value) {
	return mix(value * 12.92, 1.055 * pow(max(value, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), value));
}

void vertex() {
	float weight = pow(clamp(VERTEX.y / tree_height, 0.0, 1.0), 1.7);
	float phase = MODEL_MATRIX[3].x * 0.63 + MODEL_MATRIX[3].z * 0.41;
	VERTEX.x += sin(TIME * 1.25 + phase + VERTEX.y * 0.45) * wind_strength * weight;
	VERTEX.z += sin(TIME * 1.63 + phase + VERTEX.x) * wind_strength * weight * 0.45;
}

void fragment() {
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(COLOR.rgb) : COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
