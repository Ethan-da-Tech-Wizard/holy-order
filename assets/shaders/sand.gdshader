shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_pos;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float n=noise(world_pos.xz*0.24)*0.5+noise(world_pos.xz*2.8)*0.2+noise(world_pos.xz*32.0)*0.07;
 float ripple=sin(world_pos.x*5.2+world_pos.z*2.0+noise(world_pos.xz)*3.0)*0.018;
 ALBEDO=mix(vec3(0.43,0.35,0.24),vec3(0.72,0.60,0.41),n+ripple+0.18);
 float road=1.0-smoothstep(2.7,3.3,abs(world_pos.x-42.0));
 float tracks=1.0-smoothstep(0.10,0.23,abs(abs(world_pos.x-42.0)-1.1));
 ALBEDO=mix(ALBEDO,ALBEDO*vec3(0.72,0.77,0.82),road*0.60);
 ALBEDO*=1.0-tracks*0.15;
 ROUGHNESS=0.96;
}
