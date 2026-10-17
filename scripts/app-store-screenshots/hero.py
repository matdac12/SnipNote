"""Render the App Store product page header (3840x1646) and search results asset (3840x2560).

Usage: python3 hero.py <iphone-raw-dir> <out-dir> [en|it]
Key content stays inside the art safe areas measured from Apple's templates:
header 1646x660 centered, search results 2165x1027 centered.
"""
import os, subprocess, sys, tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

TEXT = {
    "en": ("Meetings,<br>handled.", "Record, transcribe and summarize, right on your iPhone."),
    "it": ("Riunioni,<br>sotto controllo.", "Registra, trascrivi e riassumi, direttamente sul tuo iPhone."),
}

BASE_CSS = """
html,body{margin:0;overflow:hidden;background:#0b0b0c}
body{font-family:-apple-system,"SF Pro Display",system-ui,sans-serif;color:#fff;position:relative}
.bg{position:absolute;inset:0}
.phone{position:absolute;overflow:hidden;background:#000;
  box-shadow:0 60px 160px rgba(0,0,0,.65),0 0 0 6px #2a2a2d,0 0 0 9px rgba(255,255,255,.06)}
.phone img{display:block;width:100%;height:100%;object-fit:cover}
"""

HEADER = """<!doctype html><html><head><meta charset="utf-8"><style>{css}
html,body{{width:3840px;height:1646px}}
.bg{{background:radial-gradient(ellipse 2600px 1400px at 1920px 824px,rgba(255,107,53,.42),rgba(255,107,53,0) 68%),
  linear-gradient(180deg,#151517,#0b0b0c)}}
.widget{{position:absolute;left:1120px;top:502px;width:1600px;height:643px;border-radius:84px;overflow:hidden;
  background:url(file://{widget}) center/cover;box-shadow:0 70px 180px rgba(0,0,0,.6),0 0 0 3px rgba(255,255,255,.08)}}
</style></head><body><div class="bg"></div>
<div class="phone" style="left:250px;top:120px;width:690px;height:1500px;border-radius:96px;transform:rotate(-9deg)"><img src="file://{left}"></div>
<div class="phone" style="left:2900px;top:120px;width:690px;height:1500px;border-radius:96px;transform:rotate(9deg)"><img src="file://{right}"></div>
<div class="widget"></div>
</body></html>"""

SEARCH = """<!doctype html><html><head><meta charset="utf-8"><style>{css}
html,body{{width:3840px;height:2560px}}
.bg{{background:radial-gradient(ellipse 3000px 2000px at 2300px 1280px,rgba(255,107,53,.40),rgba(255,107,53,0) 66%),
  linear-gradient(180deg,#151517,#0b0b0c)}}
.text{{position:absolute;left:850px;top:766px;width:1150px;height:1027px;display:flex;flex-direction:column;justify-content:center}}
h1{{margin:0;font-size:215px;line-height:.98;font-weight:800;letter-spacing:-.035em}}
p{{margin:60px 0 0;font-size:70px;line-height:1.28;color:rgba(255,255,255,.7);font-weight:500;text-wrap:balance}}
</style></head><body><div class="bg"></div>
<div class="text"><h1>{title}</h1><p>{sub}</p></div>
<div class="phone" style="left:2440px;top:700px;width:540px;height:1174px;border-radius:76px;transform:rotate(7deg)"><img src="file://{back}"></div>
<div class="phone" style="left:2020px;top:676px;width:580px;height:1260px;border-radius:82px"><img src="file://{front}"></div>
</body></html>"""


def render(page, size, target):
    tmp = tempfile.mkdtemp()
    path = os.path.join(tmp, "page.html")
    open(path, "w").write(page)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                    f"--window-size={size[0]},{size[1]}", "--force-device-scale-factor=1", f"--screenshot={target}",
                    "file://" + path], check=True, capture_output=True)
    # App Store Connect wants PNG without an alpha channel: round-trip through JPEG to drop it.
    jpeg = target[:-4] + ".jpg"
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "95", target, "--out", jpeg], check=True, capture_output=True)
    subprocess.run(["sips", "-s", "format", "png", jpeg, "--out", target], check=True, capture_output=True)
    os.remove(jpeg)
    print("wrote", target)


def main():
    raw = os.path.abspath(sys.argv[1])
    out = os.path.abspath(sys.argv[2])
    lang = sys.argv[3] if len(sys.argv) > 3 else "en"
    os.makedirs(out, exist_ok=True)
    widget = os.path.join(out, ".widget.png")
    # The Record + streak card on Home, cut to its edges.
    subprocess.run(["sips", "-c", "482", "1200", "--cropOffset", "500", "60", os.path.join(raw, "01-home.png"),
                    "--out", widget], check=True, capture_output=True)
    shot = lambda name: os.path.join(raw, name + ".png")
    render(HEADER.format(css=BASE_CSS, widget=widget, left=shot("03-detail"), right=shot("02-transcriptions")),
           (3840, 1646), os.path.join(out, "product-page-header.png"))
    title, sub = TEXT[lang]
    render(SEARCH.format(css=BASE_CSS, title=title, sub=sub, front=shot("01-home"), back=shot("03-detail")),
           (3840, 2560), os.path.join(out, "search-results.png"))


if __name__ == "__main__":
    main()
