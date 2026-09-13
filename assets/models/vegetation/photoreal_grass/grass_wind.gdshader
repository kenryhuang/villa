shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform float wind_strength = 0.022;
varying float blade_height;

vec3 linear_to_srgb(vec3 value) {
	return mix(value * 12.92, 1.055 * pow(max(value,vec3(0.0)),vec3(1.0/2.4)) - 0.055, step(vec3(0.0031308),value));
}

void vertex() {
	blade_height = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	float phase = world.x * 1.7 + world.z * 1.3;
	float weight = UV.y * UV.y;
	VERTEX.x += sin(TIME * 1.5 + phase) * wind_strength * weight;
	VERTEX.z += sin(TIME * 1.1 + phase * 0.7) * wind_strength * weight * 0.55;
	// Sink short blades into the existing ground at the far limit without alpha.
	float far_weight = 1.0 - smoothstep(34.0,44.0,distance(CAMERA_POSITION_WORLD,world));
	VERTEX.y *= far_weight;
}

void fragment() {
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(COLOR.rgb) : COLOR.rgb;
	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
