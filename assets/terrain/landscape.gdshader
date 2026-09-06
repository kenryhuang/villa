shader_type spatial;
render_mode cull_back;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 cliff_color : source_color = vec3(0.53, 0.51, 0.43);
varying vec3 world_point;
varying vec3 world_normal;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float hash(vec3 p) {
	return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);
}
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void fragment() {
	vec3 grass = texture(grass_texture, (world_point.xz + vec2(22.0)) / 3.666667).rgb;
	float slope = 1.0 - abs(normalize(world_normal).y);
	float rock = smoothstep(0.15,0.43,slope);
	rock = max(rock,smoothstep(17.0,26.0,world_point.y)*0.85);
	float broad = noise(world_point*vec3(.5,1.4,.5));
	float brush = noise(world_point*3.0)*.6+noise(world_point*11.0)*.4;
	float strata = smoothstep(.78,.94,noise(world_point*vec3(.18,2.5,.18)));
	vec3 stone = cliff_color*(.72+broad*.34+brush*.25-strata*.12);
	float shore = (1.0-smoothstep(-.85,.20,world_point.y)) * step(-5.0,world_point.y);
	vec3 base = mix(grass,stone,rock);
	base = mix(base,vec3(.42,.37,.22),shore*.65);
	ALBEDO = base;
	ROUGHNESS = 0.96;
}
