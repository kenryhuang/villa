shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform float wind_strength = 0.04;
uniform float tree_height = 6.0;
uniform bool foliage = false;

void vertex() {
	vec3 world_base = MODEL_MATRIX[3].xyz;
	float weight = pow(clamp(VERTEX.y / tree_height, 0.0, 1.0), 1.7);
	float phase = world_base.x * 0.63 + world_base.z * 0.41;
	float sway = sin(TIME * 1.25 + phase + VERTEX.y * 0.45);
	VERTEX.x += sway * wind_strength * weight;
	VERTEX.z += sin(TIME * 1.63 + phase + VERTEX.x) * wind_strength * weight * 0.45;
	if (foliage) {
		// Crown-shaped normals give small two-sided leaves a softer painted light.
		NORMAL = normalize(mix(NORMAL, normalize(VERTEX - vec3(0.0, tree_height * 0.62, 0.0)), 0.30));
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
