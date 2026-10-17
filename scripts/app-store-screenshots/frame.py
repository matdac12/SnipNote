"""Render captioned App Store screenshots with headless Chrome.

Usage: python3 frame.py <raw-dir> <out-dir> <iphone|ipad> [en|it]
"""
import html, os, subprocess, sys, tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SIZES = {"iphone": (1320, 2868), "ipad": (2064, 2752)}

# Order is the App Store order: the first three also show in search results.
SHOTS = {
    "en": [
        ("01-home", "Your meetings, handled", "Record, transcribe and summarize, right on your iPhone."),
        ("03-detail", "Summaries you can act on", "Key points, decisions and next steps from every meeting."),
        ("11-recording", "Free transcription", "Local mode transcribes on your iPhone. No account needed."),
        ("02-transcriptions", "Every meeting in one place", "Transcripts and summaries, always at hand."),
        ("06-search", "Find anything you said", "Search across every transcript and summary."),
        ("09-transcription", "Private by design", "In Local mode, your audio never leaves your iPhone."),
        ("10-dictation", "Dictate in any app", "The SnipNote keyboard turns your voice into text."),
    ],
    "it": [
        ("01-home", "Le tue riunioni, sotto controllo", "Registra, trascrivi e riassumi, direttamente sul tuo iPhone."),
        ("03-detail", "Riepiloghi concreti", "Punti chiave, decisioni e prossimi passi di ogni riunione."),
        ("11-recording", "Trascrizione gratuita", "La modalità Locale trascrive sul tuo iPhone. Senza account."),
        ("02-transcriptions", "Tutte le riunioni in un posto", "Trascrizioni e riepiloghi, sempre a portata di mano."),
        ("06-search", "Trova tutto ciò che hai detto", "Cerca in ogni trascrizione e riepilogo."),
        ("09-transcription", "Privacy by design", "In modalità Locale l'audio non lascia mai il tuo iPhone."),
        ("10-dictation", "Detta in qualsiasi app", "La tastiera SnipNote trasforma la voce in testo."),
    ],
}

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;width:{w}px;height:{h}px;overflow:hidden}}
body{{background:#0b0b0c;font-family:-apple-system,"SF Pro Display",system-ui,sans-serif;
  position:relative;color:#fff}}
.glow{{position:absolute;inset:0;background:
  radial-gradient(ellipse {gw}px {gh}px at 50% {gy}px, rgba(255,107,53,.38), rgba(255,107,53,0) 70%),
  linear-gradient(180deg,#141416 0%,#0b0b0c 55%)}}
.text{{position:absolute;top:{ty}px;left:0;right:0;text-align:center;padding:0 {pad}px}}
h1{{text-wrap:balance;margin:0;font-size:{h1}px;line-height:1.08;font-weight:800;letter-spacing:-.02em}}
p{{text-wrap:balance;margin:{pg}px 0 0;font-size:{p}px;line-height:1.3;color:rgba(255,255,255,.66);font-weight:500}}
.shot{{position:absolute;left:50%;top:{sy}px;width:{sw}px;transform:translateX(-50%);
  border-radius:{r}px;overflow:hidden;box-shadow:0 40px 120px rgba(0,0,0,.6),0 0 0 3px rgba(255,255,255,.08)}}
.shot img{{display:block;width:100%}}
</style></head><body><div class="glow"></div>
<div class="text"><h1>{title}</h1><p>{sub}</p></div>
<div class="shot"><img src="file://{img}"></div></body></html>"""


def layout(device, w, h):
    if device == "iphone":
        sw = 960
        return dict(sw=sw, sy=650, ty=200, h1=104, p=50, pg=34, pad=90, r=86, gw=1500, gh=1100, gy=760)
    sw = 1500
    return dict(sw=sw, sy=640, ty=190, h1=112, p=54, pg=34, pad=200, r=56, gw=2300, gh=1300, gy=760)


def main():
    raw, out, device = sys.argv[1], sys.argv[2], sys.argv[3]
    lang = sys.argv[4] if len(sys.argv) > 4 else "en"
    w, h = SIZES[device]
    os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp()
    for index, (name, title, sub) in enumerate(SHOTS[lang], start=1):
        img = os.path.join(raw, name + ".png")
        if not os.path.exists(img):
            print("missing", img)
            continue
        if device == "ipad":
            title, sub = title.replace("iPhone", "iPad"), sub.replace("iPhone", "iPad")
        page = PAGE.format(w=w, h=h, title=html.escape(title), sub=html.escape(sub), img=img, **layout(device, w, h))
        page_path = os.path.join(tmp, name + ".html")
        open(page_path, "w").write(page)
        target = os.path.join(out, f"{index:02d}-{name.split('-', 1)[1]}.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                        f"--window-size={w},{h}", "--force-device-scale-factor=1", f"--screenshot={target}",
                        "file://" + page_path], check=True, capture_output=True)
        print("wrote", target)


if __name__ == "__main__":
    main()
