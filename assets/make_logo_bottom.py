from PIL import Image, ImageDraw, ImageFont, ImageEnhance
S = 512
src = Image.open(r"D:\ai\wow\assets\campfire.webp").convert("RGB")
inner = 448
icon = src.resize((inner, inner), Image.LANCZOS)
icon = ImageEnhance.Brightness(icon).enhance(0.5)

mask = Image.new("L", (inner, inner), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], radius=56, fill=255)

canvas = Image.new("RGBA", (S, S), (18, 16, 14, 255))
d = ImageDraw.Draw(canvas)
d.rounded_rectangle([4, 4, S - 5, S - 5], radius=64, fill=(28, 24, 20, 255), outline=(214, 178, 74, 255), width=6)
canvas.paste(icon, (32, 32), mask)

# 底部渐暗，给文字压住背景
grad = Image.new("L", (S, 120), 0)
gd = ImageDraw.Draw(grad)
for i in range(120):
    gd.line([(0, i), (S, i)], fill=int(150 * (i / 119)))
canvas.paste(Image.new("RGBA", (S, 120), (10, 8, 6, 255)), (0, S - 120), grad)

d = ImageDraw.Draw(canvas)
text = "AzerothCamp"
font = None
for sz in range(58, 28, -2):
    f = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", sz)
    bbox = d.textbbox((0, 0), text, font=f, stroke_width=5)
    if bbox[2] - bbox[0] <= 372:   # 左右各留 70px，避开圆角
        font = f
        break

bbox = d.textbbox((0, 0), text, font=font, stroke_width=5)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
x = (S - tw) / 2 - bbox[0]
y = 380 - bbox[1]                 # 视觉中线约在 380，距底边 130px
d.text((x, y), text, font=font, fill=(200, 24, 24, 255), stroke_width=5, stroke_fill=(255, 214, 64, 255))

canvas.convert("RGB").save(r"D:\ai\wow\assets\logo-camp-bottom.png", "PNG")
print("ok")
