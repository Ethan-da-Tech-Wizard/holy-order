shader_type spatial;
uniform sampler2D sand_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec2 uv=wp.xz*0.32;
 vec3 sand=texture(sand_color,uv).rgb;
 vec3 stone=texture(stone_color,wp.xz*0.19).rgb;
 float inland=smoothstep(5.0,17.0,wp.y);
 float shingle=smoothstep(110.0,120.0,-wp.z)*(1.0-smoothstep(128.0,138.0,-wp.z));
 float slope=1.0-smoothstep(0.65,0.92,wn.y);
 vec3 grass=mix(stone*vec3(0.42,0.53,0.30),stone,clamp(slope*1.2,0.0,1.0));
 ALBEDO=mix(mix(sand*vec3(0.75,0.78,0.80),stone,shingle*0.85),grass,inland);
 float urban=smoothstep(334.0,354.0,-wp.z)*(1.0-smoothstep(170.0,192.0,abs(wp.x)));
 float rx=abs(mod(wp.x+19.0,38.0)-19.0);
 float rz=min(min(abs(wp.z+358.0),abs(wp.z+408.0)),min(abs(wp.z+452.0),abs(wp.z+498.0)));
 float road=max(1.0-smoothstep(5.8,7.0,rx),1.0-smoothstep(3.5,4.6,rz));
 vec2 cobble=vec2(wp.x*2.3+mod(floor(wp.z*3.8),2.0)*0.5,wp.z*3.8);
 vec2 edges=min(fract(cobble),1.0-fract(cobble));
 float mortar=1.0-smoothstep(0.02,0.08,min(edges.x,edges.y));
 vec3 paving=mix(stone*vec3(0.68,0.64,0.57),stone*0.52,road)*(1.0-mortar*0.14);
 ALBEDO=mix(ALBEDO,paving,urban);
 float wet=1.0-smoothstep(-0.1,2.0,wp.y);
 ALBEDO*=mix(1.0,0.58,wet);
 ROUGHNESS=mix(0.91,0.30,wet);
 SPECULAR=0.32;
}
