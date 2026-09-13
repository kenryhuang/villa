shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

vec3 linear_to_srgb(vec3 value) {
	return mix(value*12.92,1.055*pow(max(value,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),value));
}

void fragment() {
	// glTF COLOR_0 is linear. Compatibility shades in sRGB output space.
	ALBEDO = OUTPUT_IS_SRGB ? linear_to_srgb(COLOR.rgb) : COLOR.rgb;
	ROUGHNESS = 0.71;
	SPECULAR = 0.15;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
