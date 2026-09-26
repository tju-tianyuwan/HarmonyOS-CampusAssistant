"""Check optical continuity, overlapping screens and the seamless loop.

Start the local static server, then run: python demo-site/check_film.py
"""
from pathlib import Path
from io import BytesIO
import json
from PIL import Image, ImageChops, ImageStat, ImageDraw
from playwright.sync_api import sync_playwright

SITE = Path(__file__).resolve().parent
OUT = SITE.parent / '.codex-run' / 'film-motion-checks'
OUT.mkdir(parents=True, exist_ok=True)
with sync_playwright() as runtime:
    chrome = Path('C:/Program Files/Google/Chrome/Application/chrome.exe')
    browser = runtime.chromium.launch(headless=True, **({'executable_path':str(chrome)} if chrome.exists() else {}))
    page = browser.new_page(viewport={'width':1920,'height':1080}, device_scale_factor=1)
    errors=[]
    page.on('pageerror',lambda error:errors.append(str(error)))
    page.goto('http://127.0.0.1:4173/film.html',wait_until='networkidle')
    page.evaluate('async()=>{await window.filmReady}')

    def frame(time):
        return page.evaluate('t=>{const state=window.renderFilm(t);const d=document.querySelector("#device");const r=d.getBoundingClientRect();return {...state,opacity:getComputedStyle(d).opacity,rect:[r.x,r.y,r.width,r.height],layers:[...document.querySelectorAll(".screen-layer")].map(e=>({opacity:Number(e.style.opacity),z:Number(e.style.zIndex)}))}}',time)

    checks=[]
    for boundary in [6,12,18,24,26.1,27.4,31.4]:
        before=frame(boundary-1/60)
        after=frame(boundary+1/60)
        camera_step=max(abs(a-b) for a,b in zip(before['rect'],after['rect']))
        assert camera_step < .2, (boundary,camera_step)
        middle=frame(boundary)
        assert middle['opacity']=='1'
        assert len([l for l in middle['layers'] if l['opacity']>0])==2
        assert any(l['opacity']==1 for l in middle['layers'])
        assert any(abs(l['opacity']-.5)<.001 for l in middle['layers'])
        checks.append({'boundary':boundary,'camera_delta_pixels':round(camera_step,4),'opaque_base':True})

    contact=Image.new('RGB',(1200,1410),'#071321')
    draw=ImageDraw.Draw(contact)
    for index,time in enumerate([5.35,5.7,6.0,6.3,6.65,27.4]):
        frame(time)
        shot=Image.open(BytesIO(page.screenshot())).convert('RGB')
        shot.thumbnail((600,338))
        x=(index%2)*600
        y=(index//2)*470
        contact.paste(shot,(x,y+34))
        draw.text((x+20,y+12),f't = {time:.2f}s',fill='#b4cde4')
    contact.save(OUT/'transition-contact.jpg',quality=92)

    frame(0)
    start=Image.open(BytesIO(page.screenshot())).convert('RGB').crop((0,0,1920,1078))
    frame(32)
    end=Image.open(BytesIO(page.screenshot())).convert('RGB').crop((0,0,1920,1078))
    difference=ImageStat.Stat(ImageChops.difference(start,end)).mean
    assert max(difference)<.1, difference
    assert not errors,errors
    print(json.dumps({'result':'PASS','transitions':checks,'loop_mean_pixel_difference':difference,'page_errors':errors},indent=2))
    browser.close()
