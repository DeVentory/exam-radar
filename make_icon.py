"""앱 아이콘: 밤하늘 위 레이더 원과 회전 빔, 시험 점 하나."""
import math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((100, 100, 924, 924), 185, fill=255)
bg = Image.new("RGBA", (S, S), (9, 14, 32, 255))
g = ImageDraw.Draw(bg)
for r in range(420, 0, -6):  # 가운데가 밝은 원형 그라데이션
    c = int(14 + (420 - r) * 0.06)
    g.ellipse((512 - r, 512 - r, 512 + r, 512 + r), fill=(c, c + 8, c + 34, 255))
d = ImageDraw.Draw(bg, "RGBA")
for r in (110, 210, 310):
    d.ellipse((512 - r, 512 - r, 512 + r, 512 + r), outline=(124, 196, 255, 150), width=10)
d.line((512, 200, 512, 824), fill=(124, 196, 255, 70), width=6)
d.line((200, 512, 824, 512), fill=(124, 196, 255, 70), width=6)
beam = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(beam)
for k in range(40):  # 빔 꼬리
    a = -60 + k
    bd.pieslice((202, 202, 822, 822), a, a + 1.2, fill=(255, 196, 107, int(6 + k * 4)))
bg = Image.alpha_composite(bg, beam)
d = ImageDraw.Draw(bg, "RGBA")
x, y = 512 + 250 * math.cos(math.radians(-25)), 512 + 250 * math.sin(math.radians(-25))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((x - 70, y - 70, x + 70, y + 70), fill=(255, 196, 107, 160))
bg = Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(30)))
ImageDraw.Draw(bg).ellipse((x - 30, y - 30, x + 30, y + 30), fill=(255, 220, 150, 255))
ImageDraw.Draw(bg).ellipse((492, 492, 532, 532), fill=(232, 236, 255, 255))
img.paste(bg, (0, 0), mask)

out = sys.argv[1]
os.makedirs(out + "/AppIcon.iconset", exist_ok=True)
for s in (16, 32, 128, 256, 512):
    img.resize((s, s), Image.LANCZOS).save(f"{out}/AppIcon.iconset/icon_{s}x{s}.png")
    img.resize((s * 2, s * 2), Image.LANCZOS).save(f"{out}/AppIcon.iconset/icon_{s}x{s}@2x.png")
subprocess.run(["iconutil", "-c", "icns", f"{out}/AppIcon.iconset", "-o", f"{out}/AppIcon.icns"], check=True)
img.save(f"{out}/icon_preview.png")
