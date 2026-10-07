# renders captured terminal text into terminal-window PNGs
import sys, glob, os, re
from PIL import Image, ImageDraw, ImageFont
F = ImageFont.truetype(r"C:\Windows\Fonts\consola.ttf", 26)
FB = ImageFont.truetype(r"C:\Windows\Fonts\consolab.ttf", 26)
W_CH, LH, PAD, BAR = 14.3, 34, 28, 56
def render(src, dst, title):
    lines = open(src, encoding="utf-8").read().expandtabs(8).rstrip("\n").replace("LAPTOP","lenovo-LOQ11").split("\n")
    cols = max(90, min(140, max(len(l) for l in lines)))
    wrapped = []
    for l in lines:
        while len(l) > cols: wrapped.append(l[:cols]); l = l[cols:]
        wrapped.append(l)
    w = int(cols * W_CH + 2 * PAD); h = BAR + PAD * 2 + LH * len(wrapped)
    im = Image.new("RGB", (w, h), "#300a24"); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w, BAR], fill="#2c2c2c")
    for i, c in enumerate(["#ff5f56", "#ffbd2e", "#27c93f"]):
        d.ellipse([w - 40 - i * 34, 18, w - 20 - i * 34, 38], fill=c)
    d.text((PAD, 14), title, font=FB, fill="#dddddd")
    y = BAR + PAD
    for l in wrapped:
        m = re.match(r"(abhikhyath@[\w-]+)(:)(~[^$]*)(\$)(.*)", l)
        x = PAD
        if m:
            for txt, col in zip(m.groups(), ["#8ae234", "#ffffff", "#729fcf", "#ffffff", "#ffffff"]):
                d.text((x, y), txt, font=FB if col != "#ffffff" else F, fill=col); x += d.textlength(txt, font=F)
        else:
            col = "#ef2929" if "ERROR" in l else "#fce94f" if "DRY-RUN" in l else "#eeeeec"
            d.text((x, y), l, font=F, fill=col)
        y += LH
    im.save(dst)
for f in sorted(glob.glob("cap/*.txt")):
    render(f, f[:-4] + ".png", "abhikhyath@lenovo-LOQ11: ~/lab23")
print("ok")
