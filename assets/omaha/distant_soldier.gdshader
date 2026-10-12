shader_type spatial;
void vertex(){
 if(VERTEX.y<0.82 && abs(VERTEX.x)<0.26){
  float step=sin(TIME*7.8+INSTANCE_CUSTOM.r*6.28318+sign(VERTEX.x)*1.5708);
  VERTEX.z+=step*0.21*INSTANCE_CUSTOM.g*(1.0-VERTEX.y/0.82);
  VERTEX.y+=max(0.0,step)*0.10*INSTANCE_CUSTOM.g;
 }
}
void fragment(){ALBEDO=COLOR.rgb;ROUGHNESS=0.88;}
