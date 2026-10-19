#!/opt/homebrew/bin/python3
"""SE 중간고사 D-day 바탕화면. launchd가 매일 0시·13시·로그인 때 실행.
모든 데스크톱 공간(Spaces)에 적용하려고 바탕화면 설정 파일(Index.plist)에서 이 스크립트가 만든 그림을 가리키는 항목을 함께 바꾼다.
시험이 끝나면(10/22 13:00 KST 이후) 원래 배경으로 복원하고 예약을 스스로 지운다."""
import math, random, subprocess, glob, os, plistlib
from pathlib import Path
from datetime import datetime, timezone, timedelta
from PIL import Image, ImageDraw, ImageFont, ImageFilter

KST = timezone(timedelta(hours=9))
EXAM = datetime(2026, 10, 22, 10, 30, tzinfo=KST)
PLACE = ""  # 시험 장소. 비워 두면 날짜·시간만 보여준다
END = datetime(2026, 10, 22, 13, 0, tzinfo=KST)
HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, "Pictures/claude-wallpaper")
LABEL = "com.claude.sewallpaper"
PLIST = os.path.join(HOME, f"Library/LaunchAgents/{LABEL}.plist")
W, H = 3024, 1964
FIXED = os.path.join(DIR, "se-dday.png")  # 모든 데스크톱 공간이 가리키는 고정 파일
STORE = os.path.join(HOME, "Library/Application Support/com.apple.wallpaper/Store/Index.plist")

GOTHIC = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
EMOJI = "/System/Library/Fonts/Apple Color Emoji.ttc"


def set_wallpaper(path):
    subprocess.run(["osascript", "-e",
                    f'tell application "System Events" to tell every desktop to set picture to POSIX file "{path}"'],
                   check=False)
    point_all_spaces(path)


def point_all_spaces(path):
    """osascript는 지금 보고 있는 공간만 바꾼다. 바탕화면 설정 파일에서
    이 스크립트가 만든 그림(claude-wallpaper)을 가리키는 항목을 모든 공간에서 path로 바꾸고 다시 읽게 한다."""
    try:
        with open(STORE, "rb") as f:
            store = plistlib.load(f)
    except (OSError, plistlib.InvalidFileException):
        return
    uri = Path(path).as_uri()
    changed = 0

    def fix(o):
        nonlocal changed
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "Configuration" and isinstance(v, bytes) and v:
                    try:
                        inner = plistlib.loads(v)
                    except Exception:
                        continue
                    url = inner.get("url", {}) if isinstance(inner, dict) else {}
                    if "claude-wallpaper" in url.get("relative", "") and url["relative"] != uri:
                        url["relative"] = uri
                        fmt = plistlib.FMT_BINARY if v.startswith(b"bplist") else plistlib.FMT_XML
                        o[k] = plistlib.dumps(inner, fmt=fmt)
                        changed += 1
                else:
                    fix(v)
        elif isinstance(o, list):
            for v in o:
                fix(v)

    fix(store)
    if changed:
        with open(STORE, "wb") as f:
            plistlib.dump(store, f, fmt=plistlib.FMT_BINARY)
    subprocess.run(["killall", "WallpaperAgent"], check=False, capture_output=True)


def restore():
    with open(os.path.join(HOME, ".wallpaper_backup.txt")) as f:
        set_wallpaper(f.read().strip())
    if os.path.exists(PLIST):
        os.remove(PLIST)
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], check=False)


def font(size, idx=0):
    return ImageFont.truetype(GOTHIC, size, index=idx)  # ttc index: 0 Regular … 6 Bold 근처


def emoji(ch, size):
    f = ImageFont.truetype(EMOJI, 160)
    im = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((20, 20), ch, font=f, embedded_color=True)
    im = im.crop(im.getbbox())
    return im.resize((size, int(size * im.height / im.width)), Image.LANCZOS)


def ctext(d, y, s, f, fill):
    w = d.textlength(s, font=f)
    d.text(((W - w) / 2, y), s, font=f, fill=fill)


def draw(now):
    rnd = random.Random(20261022)
    img = Image.new("RGB", (W, H), (7, 11, 24))
    # 은은한 성운
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    for cx, cy, r, col in [(900, 600, 700, (30, 50, 120)), (2300, 1300, 800, (70, 30, 90)), (1600, 900, 500, (20, 60, 90))]:
        g.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(260))
    img = Image.blend(img, glow, 0.55)
    d = ImageDraw.Draw(img, "RGBA")
    # 배경 별
    for _ in range(900):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        r = rnd.choice([1, 1, 1.5, 2, 2.5])
        d.ellipse((x - r, y - r, x + r, y + r), fill=(210, 220, 255, rnd.randint(60, 200)))
    # 작은 별자리 몇 개
    for _ in range(5):
        cx, cy = rnd.choice([rnd.uniform(260, 700), rnd.uniform(2320, 2760)]), rnd.choice([rnd.uniform(140, 420), rnd.uniform(1500, 1750)])
        pts = [(cx + rnd.uniform(-220, 220), cy + rnd.uniform(-110, 110)) for _ in range(5)]
        d.line(pts, fill=(90, 110, 190, 90), width=2)
        for x, y in pts:
            d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=(240, 244, 255, 230))

    days = (EXAM.date() - now.date()).days
    big = "D-DAY" if days <= 0 else f"D-{days}"
    sub = "오늘이에요. 아는 만큼 침착하게" if days <= 0 else "소프트웨어공학 중간고사까지"

    ctext(d, 330, sub, font(64, 0), (170, 180, 220))
    fb = font(380, 6)
    bw = d.textlength(big, font=fb)
    em = emoji("🧩", 260)
    total = em.width + 60 + bw
    x0 = (W - total) / 2
    img.paste(em, (int(x0), 520), em)
    d.text((x0 + em.width + 60, 400), big, font=fb, fill=(255, 196, 107))
    when = f"{EXAM.month}월 {EXAM.day}일 ({'월화수목금토일'[EXAM.weekday()]}) {EXAM:%H:%M}"
    ctext(d, 900, when + (f"  ·  {PLACE}" if PLACE else ""), font(70, 4), (232, 236, 255))

    cards = [("01 · p7", "화이트박스", ["= 구조 기반 테스트", "블랙박스 = 명세 기반"]),
             ("01 · p11", "폭포수 모델", ["선형 순차적 모델", "= 고전적 생명 주기"]),
             ("02 · p23–24", "포함 vs 선행 조건", ["피포함 = 2개 이상의", "공통 부분(이벤트 흐름)"]),
             ("02 · p25", "확장 관계", ["점선 <<extend>>", "확장 → 기본 유스케이스"]),
             ("04 · p14–19", "결합도 (좋은 순)", ["데이터 < 스탬프 < 제어", "< 공통 < 내용"])]
    cw, ch, gap = 540, 330, 24
    sx = (W - (cw * 5 + gap * 4)) / 2
    y = 1170

    def fit(s, size, idx, maxw):
        while size > 20 and d.textlength(s, font=font(size, idx)) > maxw:
            size -= 1
        return font(size, idx)

    for i, (tag, title, lines) in enumerate(cards):
        x = sx + i * (cw + gap)
        d.rounded_rectangle((x, y, x + cw, y + ch), 32, fill=(14, 21, 48, 200), outline=(60, 72, 130, 255), width=3)
        d.text((x + 36, y + 30), tag, font=font(30, 2), fill=(124, 196, 255))
        d.text((x + 36, y + 76), title, font=fit(title, 50, 6, cw - 72), fill=(255, 196, 107))
        for k, line in enumerate(lines):
            d.text((x + 36, y + 170 + k * 56), line, font=fit(line, 38, 2, cw - 72), fill=(232, 236, 255))
    ctext(d, 1580, "자주 놓친 개념 5  ·  강의자료 문구 그대로  ·  시험이 끝나면 원래 배경으로 돌아가요", font(34, 0), (110, 120, 160))
    return img


def main():
    now = datetime.now(KST)
    if now >= END:
        restore()
        return
    for old in glob.glob(os.path.join(DIR, "se-dday-*.png")):
        os.remove(old)
    tmp = FIXED + ".tmp.png"
    draw(now).save(tmp)
    os.replace(tmp, FIXED)
    set_wallpaper(FIXED)


if __name__ == "__main__":
    import sys
    if "--restore" in sys.argv:  # 지금 바로 원래 배경으로 (restore_wallpaper.sh)
        restore()
    else:
        main()
