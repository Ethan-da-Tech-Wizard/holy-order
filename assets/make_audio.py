"""Generate original sound effects; no sampled or licensed game audio."""
from pathlib import Path
import math, random, wave, struct
out=Path(__file__).parent/'audio';out.mkdir(exist_ok=True)
sr=22050
random.seed(6141940)
def save(name,seconds,fn):
 data=bytearray()
 for i in range(int(seconds*sr)):
  t=i/sr
  v=max(-.97,min(.97,fn(t)))
  data.extend(struct.pack('<h',int(v*32767)))
 with wave.open(str(out/(name+'.wav')),'wb') as w:
  w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes(data)
noise=lambda:random.uniform(-1,1)
save('rifle',.9,lambda t:noise()*(.76*math.exp(-t*34)+.14*math.exp(-t*5)) + math.sin(t*math.tau*(90-25*t))*.25*math.exp(-t*17))
save('bolt',.38,lambda t:noise()*(.2*math.exp(-t*75)+.28*math.exp(-abs(t-.22)*100))+.07*math.sin(2800*t)*math.exp(-abs(t-.21)*45))
save('sword',.5,lambda t:noise()*.25*math.sin(min(1,t/.5)*math.pi)**2+.035*math.sin(t*math.tau*440)*math.exp(-t*5))
save('hit',.35,lambda t:noise()*.25*math.exp(-t*35)+.28*math.sin(t*math.tau*75)*math.exp(-t*22))
save('clang',.75,lambda t:sum(math.sin(t*math.tau*f)*a for f,a in [(560,.17),(897,.12),(1413,.08)])*math.exp(-t*7)+noise()*.17*math.exp(-t*50))
save('step',.22,lambda t:noise()*.21*math.exp(-t*25)+.08*math.sin(t*220)*math.exp(-t*35))
save('reload',1.9,lambda t:noise()*sum(.18*math.exp(-abs(t-p)*90) for p in [.05,.55,1.1,1.55,1.76]))
save('victory',3.6,lambda t:sum(math.sin(t*math.tau*f)*.11 for f in [146.83,220,293.66,349.23])*min(t*2,1)*math.exp(-t*.85))
# Loop lengths are integral for periodic components; softly filtered noise supplies air.
last=0.0
def wind(t):
 global last
 last=last*.992+noise()*.008
 envelope=.65+.17*math.sin(math.tau*t/12)+.1*math.sin(math.tau*t/6)
 return last*envelope*1.8+.014*math.sin(math.tau*73*t)
save('wind',12,wind)
print('Generated nine original sound effects/ambience.')
