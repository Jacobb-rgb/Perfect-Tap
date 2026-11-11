# python3 make_anim.py <frames dir> <out.webp> [width] [fps]  -> a looping animated WebP
import sys, glob
from PIL import Image
d, out = sys.argv[1], sys.argv[2]
w = int(sys.argv[3]) if len(sys.argv) > 3 else 1280
fps = int(sys.argv[4]) if len(sys.argv) > 4 else 20
files = sorted(glob.glob(d + "/*.png"))
frames = [Image.open(f).convert("RGB") for f in files]
h = round(frames[0].height * w / frames[0].width)
frames = [f.resize((w, h), Image.LANCZOS) for f in frames]
frames[0].save(out, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0, quality=80, method=4)
print(out, len(frames), "frames")
