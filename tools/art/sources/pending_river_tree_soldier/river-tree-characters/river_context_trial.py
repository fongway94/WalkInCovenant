from pathlib import Path
from PIL import Image,ImageChops,ImageStat
from math import sqrt
root=Path('build/river-tree-characters');probe=Path('build/river-tree-warrior-probe');out=root/'river-candidates'
full=Image.new('RGB',(2048,3072));full.paste(Image.open('art/scenes_painted/world_elah_refined_top.png'),(0,0));full.paste(Image.open('art/scenes_painted/world_elah_refined_bottom.png'),(0,1536))
box=(0,398*4,2048,462*4);base=full.crop(box)
source=Image.open(root/'river-detail-retry.png').convert('RGB').resize((2048,1152),Image.Resampling.NEAREST)
new=source.crop((0,(398-320)*4,2048,(462-320)*4))
mask=Image.open(probe/'water-mask-restricted.png').convert('L');assert new.size==base.size==mask.size
print('water masked mean published',ImageStat.Stat(base,mask).mean,'new',ImageStat.Stat(new,mask).mean)
for name,alpha in [('ctx35',0.35),('ctx55',0.55),('ctx75',0.75),('ctx100',1.0)]:
 blend=Image.blend(base,new,alpha)
 water=Image.composite(blend,base,mask)
 img=full.copy();img.paste(water,(0,398*4))
 d=out/name;d.mkdir(parents=True,exist_ok=True)
 for part,y in [('top',0),('bottom',1536)]:
  p=d/f'elah-{part}.png';img.crop((0,y,2048,y+1536)).save(p,compress_level=3);print('built',p,flush=True)
