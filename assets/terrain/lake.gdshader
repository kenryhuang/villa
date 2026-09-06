shader_type spatial;
render_mode cull_disabled;

varying vec3 world_point;
varying float water_depth;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	water_depth = COLOR.r * 4.0;
}

void fragment() {
	float swell = sin(world_point.x*.19+world_point.z*.13+TIME*.11);
	float wave = sin(world_point.x*6.3+world_point.z*2.7+swell*3.0+sin(world_point.z*.83+world_point.x*.29)*2.5-TIME*.7);
	float broken_crest = .5+.5*sin(world_point.z*1.1-world_point.x*.15+sin(world_point.x*.26)*2.0+TIME*.2);
	float glint = smoothstep(.88,1.0,wave)*smoothstep(.25,.85,broken_crest);
	vec3 shallow = vec3(.24,.52,.48);
	vec3 deep = vec3(.065,.29,.34);
	vec3 water = mix(shallow,deep,smoothstep(.05,2.1,water_depth));
	float shore_ripple = (1.0-smoothstep(.02,.28,water_depth))*(.5+.5*sin(world_point.x*3.0+world_point.z*2.0-TIME));
	ALBEDO = water + vec3(.006,.009,.007)*wave + vec3(.025,.04,.035)*glint + vec3(.09,.09,.06)*shore_ripple;
	ROUGHNESS = .42;
	SPECULAR = .35;
}
