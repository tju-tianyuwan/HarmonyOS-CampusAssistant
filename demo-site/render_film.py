"""Render the deterministic 1080p product film, poster and GIF.

Requires Pillow, Playwright, Chrome and ffmpeg. No external services.
Start the preview server, then: python demo-site/render_film.py
"""
from pathlib import Path
import argparse
import subprocess
import shutil
from playwright.sync_api import sync_playwright

SITE = Path(__file__).resolve().parent
ASSETS = SITE / 'assets'
WORK = SITE.parent / '.codex-run' / 'film-render'
WORK.mkdir(parents=True, exist_ok=True)
FPS = 60
parser = argparse.ArgumentParser()
parser.add_argument('--stills-only', action='store_true')
parser.add_argument('--url', default='http://127.0.0.1:4173/film.html')
args = parser.parse_args()

with sync_playwright() as runtime:
    chrome = Path('C:/Program Files/Google/Chrome/Application/chrome.exe')
    browser = runtime.chromium.launch(headless=True, **({'executable_path': str(chrome)} if chrome.exists() else {}))
    page = browser.new_page(viewport={'width':1920,'height':1080}, device_scale_factor=1)
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.goto(args.url, wait_until='networkidle')
    page.evaluate('async()=>{await window.filmReady;}')

    def render(time):
        page.evaluate('t=>window.renderFilm(t)', time)

    for index, time in enumerate([2.0, 8.5, 14.5, 20.5, 30.0]):
        render(time)
        page.screenshot(path=str(ASSETS / f'film-chapter-{index+1}.jpg'), type='jpeg', quality=94)
    shutil.copyfile(ASSETS / 'film-chapter-1.jpg', ASSETS / 'product-tour-poster.jpg')
    print('Chapter stills and poster ready.', flush=True)
    if not args.stills_only:
        ffmpeg = shutil.which('ffmpeg')
        if not ffmpeg:
            raise RuntimeError('ffmpeg is required for the video export.')
        # Encode away from the served asset, then replace only a finished movie.
        movie = WORK / 'product-film-smooth.mp4'
        command = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', str(FPS), '-vcodec', 'mjpeg', '-i', '-', '-an', '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(movie)]
        with (WORK / 'ffmpeg.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=log)
            try:
                for frame in range(32 * FPS):
                    render(frame / FPS)
                    process.stdin.write(page.screenshot(type='jpeg', quality=92))
                    if frame % (FPS * 4) == 0:
                        print(f'Film: {frame//FPS:02d} / 32 seconds at {FPS} fps', flush=True)
            finally:
                process.stdin.close()
            if process.wait() != 0:
                raise RuntimeError((WORK / 'ffmpeg.log').read_text(encoding='utf-8'))
        print('MP4 complete. Encoding 20 fps GIF...', flush=True)
        gif = WORK / 'product-tour-smooth.gif'
        subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-i', str(movie), '-filter_complex', 'fps=20,scale=854:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle', '-loop', '0', str(gif)], check=True)
        shutil.copyfile(movie, ASSETS / 'product-film.mp4')
        shutil.copyfile(gif, ASSETS / 'product-tour.gif')
        print('MP4 and GIF complete.', flush=True)
    assert not errors, errors
    browser.close()
