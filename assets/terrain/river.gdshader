shader_type spatial;
render_mode cull_disabled;

varying vec3 world_point;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	float ripples = sin(world_point.z*3.1-TIME*1.3+sin(world_point.x*2.3))*sin(world_point.x*4.7+world_point.z*.4+TIME*.4);
	float streak = smoothstep(.90,.99,sin(world_point.z*5.0-TIME*1.4+sin(world_point.x*3.3)))*smoothstep(.3,.8,sin(world_point.x*2.3+world_point.z*.8));
	ALBEDO = mix(vec3(.075,.27,.29),vec3(.22,.48,.43),.5+.18*ripples);
	ALBEDO += vec3(.15,.20,.16)*streak*.25;
	ROUGHNESS = .65;
	SPECULAR = .18;
}
