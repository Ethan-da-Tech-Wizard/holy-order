shader_type spatial;
uniform vec4 plaster_color : source_color = vec4(0.63,0.55,0.42,1.0);
varying vec3 p;
varying vec3 n;
float hash(vec3 a){ return fract(sin(dot(a,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 a){
	vec3 i=floor(a),f=fract(a); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;n=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
	float broad=noise(p*0.85);
	float grain=noise(p*36.0);
	float worn=smoothstep(0.44,0.60,noise(p*1.8)+noise(p*7.0)*0.18);
	float lower=1.0-smoothstep(0.05,1.1,p.y);
	vec2 face=vec2(abs(n.x)>abs(n.z)?p.z:p.x,p.y);
	float row=floor(face.y/0.24);
	vec2 stone=fract(vec2((face.x+mod(row,2.0)*0.28)/0.57,face.y/0.24));
	float mortar=1.0-smoothstep(0.025,0.060,min(min(stone.x,1.0-stone.x),min(stone.y,1.0-stone.y)));
	float chips=worn*(0.25+lower*0.7);
	float fade=1.0-smoothstep(0.08,0.35,length(fwidth(p)));
	vec3 plaster=plaster_color.rgb*(0.80+broad*0.26+grain*0.07*fade);
	vec3 limestone=plaster_color.rgb*vec3(0.83,0.85,0.88)*(0.8+noise(p*5.0)*0.25-mortar*0.16*fade);
	ALBEDO=mix(plaster,limestone,chips)*(1.0-lower*0.12);
	ROUGHNESS=0.91+grain*0.08;
}
