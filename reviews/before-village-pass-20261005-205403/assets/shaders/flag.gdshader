shader_type spatial;
render_mode cull_disabled;
uniform vec4 color : source_color = vec4(0.7,0.65,0.45,1.0);
void vertex(){VERTEX.z += sin(TIME*3.5+VERTEX.x*3.0)*0.14*(VERTEX.x+1.4)/2.8;}
void fragment(){ALBEDO=color.rgb;ROUGHNESS=0.92;}
