shader_type spatial;
varying vec3 local;
void vertex(){local=VERTEX;}
void fragment(){
 vec3 c=COLOR.rgb;
 float wood=step(c.g*1.13,c.r)*step(c.b*1.28,c.r);
 float grain=sin(local.z*210.0+sin(local.x*440.0)*2.0)*sin(local.z*73.0+local.x*560.0)*0.055;
 float tooling=sin(local.z*1900.0)*sin(local.x*1270.0)*0.018;
 ALBEDO=c*(1.0+mix(tooling,grain,wood));
 ROUGHNESS=mix(0.54,0.79,wood);
 METALLIC=mix(0.58,0.0,wood);
}
