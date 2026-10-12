shader_type spatial;
uniform vec4 stone_color : source_color = vec4(0.55, 0.47, 0.35, 1.0);
varying vec3 world_position;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
	vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec3 p=world_position;
	float broad=noise(p*0.65);
	float grain=noise(p*20.0);
	float strata=sin(p.y*17.0+noise(p*1.1)*5.0);
	float detail_fade=1.0-smoothstep(0.08,0.4,length(fwidth(p)));
	ALBEDO=stone_color.rgb*(0.76+broad*0.32+grain*0.10*detail_fade+strata*0.035*detail_fade);
	ROUGHNESS=0.89+grain*0.08;
}
