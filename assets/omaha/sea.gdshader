shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
void vertex(){
 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float nearshore=smoothstep(-6.0,50.0,wp.z);
 VERTEX.y+=(sin(wp.z*0.48-TIME*1.5)+sin(wp.x*0.23+wp.z*0.3-TIME*1.1))*0.10*nearshore;
}
void fragment(){
 float wave=sin(wp.x*2.4+TIME)*sin(wp.z*3.5-TIME*1.4);
 float crest=pow(max(0.0,sin(wp.z*0.48-TIME*1.5)),12.0);
 float surf=(1.0-smoothstep(-3.0,29.0,wp.z))*crest;
 ALBEDO=mix(vec3(0.055,0.095,0.105)+wave*0.018,vec3(0.50,0.56,0.54),surf*0.65);
 NORMAL_MAP=vec3(0.5+cos(wp.x*2.4+TIME)*0.08,0.5+sin(wp.z*3.5-TIME)*0.08,1.0);
 ROUGHNESS=0.24+surf*0.3;METALLIC=0.12;SPECULAR=0.70;
}
