shader_type spatial;
uniform vec4 tint : source_color = vec4(0.6,0.57,0.48,1.0);
uniform int surface_kind = 0;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;wn=abs(MODEL_NORMAL_MATRIX*NORMAL);}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
 vec2 uv=wn.y>0.6?wp.xz:(wn.x>wn.z?wp.zy:wp.xy);
 vec2 sz=surface_kind==1?vec2(0.42,0.22):vec2(0.72,0.34);
 if(surface_kind==2)sz=vec2(0.16,2.8);
 float row=floor(uv.y/sz.y);
 vec2 grid=vec2(uv.x/sz.x+mod(row,2.0)*0.5,uv.y/sz.y);
 vec2 edge=min(fract(grid),1.0-fract(grid));
 float joint=1.0-smoothstep(0.012,0.042,min(edge.x,edge.y));
 float variation=hash(floor(grid));
 float grime=hash(floor(uv*9.0))*0.07;
 vec3 base=tint.rgb*(0.86+variation*0.22-grime);
 if(surface_kind==0){
  float plaster=smoothstep(0.28,0.68,hash(floor(uv*0.48)));
  base=mix(base, tint.rgb*1.12,plaster*0.72);
  joint*=1.0-plaster*0.8;
 }
 ALBEDO=mix(base,tint.rgb*0.48,joint*0.65);
 ROUGHNESS=0.93;
}
