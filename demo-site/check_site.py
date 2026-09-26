"""Browser smoke check. Requires Playwright and an installed Chrome browser.

Start the local server described in README.md, then run:
  python demo-site/check_site.py
"""
from pathlib import Path
import json
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / '.codex-run' / 'demo-site-checks'
OUT.mkdir(parents=True, exist_ok=True)
BASE = 'http://127.0.0.1:4173'

with sync_playwright() as runtime:
    chrome = Path('C:/Program Files/Google/Chrome/Application/chrome.exe')
    browser = runtime.chromium.launch(headless=True, **({'executable_path': str(chrome)} if chrome.exists() else {}))
    page = browser.new_page(viewport={'width': 1440, 'height': 1000}, reduced_motion='reduce')
    errors = []
    failed_resources = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('response', lambda response: failed_resources.append(response.url) if response.status >= 400 else None)
    page.goto(BASE, wait_until='networkidle')
    expect(page).to_have_title('智慧伴学 · 让每一堂课，都有回响')
    page.get_by_role('link', name='体验学习之旅').click()
    page.get_by_role('button', name='课堂转写', exact=True).click()
    expect(page.get_by_role('heading', name='课堂转写片段 · 示例')).to_be_visible()
    page.get_by_role('button', name='这一点没听懂，问问 AI').click()
    page.get_by_role('button', name='中序遍历一定得到有序结果吗？', exact=True).click()
    expect(page.locator('.chat-bubble.assistant')).to_contain_text('不一定。')
    page.get_by_role('tab', name='03 小组讨论').click()
    for _ in range(5):
        page.locator('#continue-group').click()
    expect(page.locator('.group-message')).to_have_count(4)
    expect(page.locator('.summary-box')).to_contain_text('二叉搜索树')
    with page.expect_download() as summary_download:
        page.locator('#download-summary').click()
    assert '学习总结' in summary_download.value.suggested_filename
    summary = Path(summary_download.value.path()).read_text(encoding='utf-8')
    assert '核心知识点' in summary
    page.get_by_role('tab', name='04 沉淀笔记').click()
    sample_note = '# 我的理解\n\n左 → 根 → 右。\n<script>alert(1)</script>'
    page.locator('#note-content').fill(sample_note)
    page.locator('#save-note').click()
    expect(page.locator('#save-state')).to_contain_text('已保存在本次页面会话')
    page.get_by_role('tab', name='02 向 AI 提问').click()
    page.get_by_role('tab', name='04 沉淀笔记').click()
    expect(page.locator('#note-content')).to_have_value(sample_note)
    assert page.locator('#demo-panel script').count() == 0
    with page.expect_download() as note_download:
        page.locator('#download-note').click()
    assert Path(note_download.value.path()).read_text(encoding='utf-8') == sample_note
    page.get_by_role('tab', name='05 巩固练习').click()
    expect(page.locator('#submit-quiz')).to_be_disabled()
    page.locator('[data-option="0"]').click()
    page.locator('#submit-quiz').click()
    expect(page.locator('.quiz-result')).to_contain_text('正确答案是 B')
    page.locator('#retry-quiz').click()
    page.locator('[data-option="1"]').click()
    page.locator('#submit-quiz').click()
    expect(page.locator('.quiz-result')).to_contain_text('答对了')
    page.locator('#reset-demo').click()
    expect(page.locator('#tab-class')).to_have_attribute('aria-selected', 'true')
    page.locator('#tab-class').focus()
    page.keyboard.press('ArrowRight')
    expect(page.locator('#tab-ai')).to_be_focused()
    expect(page.locator('#tab-ai')).to_have_attribute('aria-selected', 'true')
    page.locator('#reset-demo').click()
    page.locator('#gallery').scroll_into_view_if_needed()
    # Native media: decode, chapter seeking, pause and time indicators.
    page.locator('#film-overlay').click()
    page.wait_for_function('document.querySelector("#product-film").currentTime > 0.3')
    expect(page.locator('#toggle-film')).to_have_attribute('aria-pressed', 'true')
    page.locator('[data-time="24"]').click()
    page.wait_for_function('document.querySelector("#product-film").currentTime >= 24')
    expect(page.locator('[data-time="24"]')).to_have_attribute('aria-pressed', 'true')
    page.locator('#toggle-film').click()
    expect(page.locator('#toggle-film')).to_have_attribute('aria-pressed', 'false')
    assert page.locator('#product-film').evaluate('(v) => v.videoWidth === 1920 && v.videoHeight === 1080')
    assert page.locator('#film-error').is_hidden()
    page.locator('.gif-disclosure > summary').click()
    expect(page.locator('#tour-gif')).to_have_attribute('src', 'assets/product-tour-poster.jpg')
    page.locator('#toggle-gif').click()
    expect(page.locator('#tour-gif')).to_have_attribute('src', 'assets/product-tour.gif?v=smooth20')
    expect(page.locator('#toggle-gif')).to_have_attribute('aria-pressed', 'true')
    page.locator('#toggle-gif').click()
    expect(page.locator('#tour-gif')).to_have_attribute('src', 'assets/product-tour-poster.jpg')
    page.locator('.capture-grid [data-image="assets/overview.jpg"]').click()
    expect(page.locator('#image-dialog')).to_be_visible()
    page.keyboard.press('Escape')
    expect(page.locator('#image-dialog')).not_to_be_visible()
    expect(page.locator('.capture-grid [data-image="assets/overview.jpg"]')).to_be_focused()
    page.locator('.gif-disclosure > summary').click()
    # Eagerly decode images for complete full-page visual inspection.
    page.evaluate("async () => { const imgs=[...document.images]; imgs.forEach(i=>i.loading='eager'); await Promise.all(imgs.filter(i=>i.src).map(i=>i.decode().catch(()=>{}))); }")
    assert page.locator('img[src]').evaluate_all('(imgs) => imgs.every(i => i.naturalWidth > 0)')
    layouts = []
    for width in [1440, 1024, 768, 390, 320]:
        page.set_viewport_size({'width': width, 'height': 1000 if width > 540 else 844})
        page.evaluate('window.scrollTo(0,0)')
        metrics = page.evaluate('({viewport:innerWidth,width:document.documentElement.scrollWidth})')
        if metrics['width'] > width:
            print(page.evaluate('Array.from(document.querySelectorAll("body *")).map(e=>({tag:e.tagName,cl:e.className,x:e.getBoundingClientRect().x,right:e.getBoundingClientRect().right,w:e.getBoundingClientRect().width})).filter(e=>e.right>innerWidth+1 || e.x < -1)'))
        assert metrics['width'] <= width, metrics
        for scene in ['class', 'ai', 'group', 'notes', 'practice']:
            page.locator(f'#tab-{scene}').click()
            assert page.locator('#demo-panel').evaluate('(e) => e.scrollWidth <= e.clientWidth + 1'), (width, scene)
        page.locator('#reset-demo').click()
        page.locator('#toast').evaluate('(e) => e.classList.remove("visible")')
        page.evaluate('window.scrollTo(0,0)')
        page.screenshot(path=str(OUT / f'page-{width}.png'), full_page=True)
        layouts.append(metrics)
    # Direct file access must work without a server or fetch-based routing.
    page.goto((ROOT / 'demo-site' / 'index.html').as_uri(), wait_until='load')
    page.get_by_role('tab', name='05 巩固练习').click()
    page.locator('[data-option="1"]').click()
    page.locator('#submit-quiz').click()
    expect(page.locator('.quiz-result')).to_contain_text('答对了')
    assert not errors, errors
    assert not failed_resources, failed_resources
    print(json.dumps({'result':'PASS','viewports':layouts,'page_errors':errors,'failed_resources':failed_resources,'screenshots':str(OUT)}, ensure_ascii=True, indent=2))
    browser.close()
