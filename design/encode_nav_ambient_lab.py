import io, struct, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops, ImageStat

root=Path(sys.argv[1]); count=int(sys.argv[2]); frames=[]
for _ in range(count):
    size=struct.unpack('<I',sys.stdin.buffer.read(4))[0]
    frames.append(Image.open(io.BytesIO(sys.stdin.buffer.read(size))).convert('RGB'))
    if frames[-1].size != (466,466):
        raise SystemExit('Native preview frame must be exactly 466 x 466')
palette=Image.new('RGB',(466,466*4))
for j,i in enumerate([0,count//4,count//2,3*count//4]): palette.paste(frames[i],(0,j*466))
palette=palette.quantize(colors=256)
indexed=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
indexed[0].save(root/'nav-ambient-lab-1x.gif',save_all=True,append_images=indexed[1:],duration=125,loop=0,optimize=True)
# Lossless true-color animation is the color review artifact. GIF is limited
# to a 256-color palette and must not be used to judge subtle dark gradients.
frames[0].save(root/'nav-ambient-lab-1x.png',save_all=True,
    append_images=frames[1:],duration=125,loop=0,compress_level=6)
sheet=Image.new('RGB',(932,500),'#151a1d')
for j,(scene,label) in enumerate([('route-only','ROUTE ONLY'),('full-design-fixture','FULL VISUAL TARGET / SYNTHETIC')]):
    sheet.paste(Image.open(root/f'nav-ambient-lab-{scene}-466.png').convert('RGB'),(j*466,0))
    ImageDraw.Draw(sheet).text((j*466+16,479),label,fill='#c8d2d2')
sheet.save(root/'nav-ambient-lab-fusion-comparison.png')
diff=ImageChops.difference(frames[0],frames[48]).crop((35,35,425,260))
print('Six-second upper-field mean pixel change:',ImageStat.Stat(diff).mean)
for frame in frames[1:]:
    hud_diff=ImageChops.difference(frames[0],frame).crop((85,350,385,422))
    if hud_diff.getbbox() is not None:
        raise SystemExit('HUD unexpectedly moved or changed color during ambient-only animation')
print('HUD pixel identity across all animation frames: verified.')
