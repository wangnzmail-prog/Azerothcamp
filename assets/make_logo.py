from PIL import Image, ImageDraw, ImageFont, ImageEnhance
S = 512
src = Image.open(r"D:\ai\wow\assets\campfire.webp").convert("RGB")
inner = 448
icon = src.resize((inner, inner), Image.LANCZOS)
icon = ImageEnhance.Brightness(icon).enhance(0.45)   # 压暗背景，突出文字

mask = Image.new("L", (inner, inner), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], radius=56, fill=255)

canvas = Image.new("RGBA", (S, S), (18, 16, 14, 255))
d = ImageDraw.Draw(canvas)
d.rounded_rectangle([4, 4, S - 5, S - 5], radius=64, fill=(28, 24, 20, 255), outline=(214, 178, 74, 255), width=6)
canvas.paste(icon, (32, 32), mask)

d = ImageDraw.Draw(canvas)
text = "AzerothCamp"
size = 62
font = None
for sz in range(size, 30, -2):
    try:
        f = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", sz)
    except Exception:
        f = ImageFont.load_default()
    bbox = d.textbbox((0, 0), text, font=f, stroke_width=6)
    if bbox[2] - bbox[0] <= 440:
        font = f
        break
if font is None:
    font = ImageFont.truetype(r"C:\Windows\Fonts\arialbd.ttf", 34)

bbox = d.textbbox((0, 0), text, font=font, stroke_width=6)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
x = (S - tw) / 2 - bbox[0]
y = (S - th) / 2 - bbox[1]
d.text((x, y), text, font=font, fill=(200, 24, 24, 255), stroke_width=6, stroke_fill=(255, 214, 64, 255))

canvas.convert("RGB").save(r"D:\ai\wow\assets\logo-camp-512.png", "PNG")
print("ok")

