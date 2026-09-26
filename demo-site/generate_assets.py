"""Build assets only from current native client captures.

No legacy screenshot files are used. See assets/captures/provenance.json.
Usage: python demo-site/generate_assets.py
"""
from pathlib import Path
from PIL import Image

SITE = Path(__file__).resolve().parent
ASSETS = SITE / 'assets'
CAPTURES = ASSETS / 'captures'
for name in ['home', 'ai', 'group', 'notes', 'practice', 'selected', 'result']:
    original = Image.open(CAPTURES / f'{name}.webp').convert('RGB')
    # Crop OS status and gesture bars, preserving the application's pixels.
    cropped = original.crop((0, 78, 2880, 1864))
    cropped.save(ASSETS / f'current-{name}.webp', quality=93, method=6)
    if name in ['home', 'group', 'notes', 'practice']:
        key = {'home': 'overview', 'group': 'discussion'}.get(name, name)
        cropped.resize((1920, 1191), Image.Resampling.LANCZOS).save(ASSETS / f'{key}.jpg', quality=93, optimize=True)
    print(f'Prepared current-{name}.webp', flush=True)
result = Image.open(CAPTURES / 'result.webp').convert('RGB')
result.crop((635, 1410, 2245, 1550)).save(ASSETS / 'practice-detail.webp', quality=95, method=6)
brand = Image.open(SITE.parent / 'assets/branding/app_logo_crystal.png').convert('RGBA')
brand.thumbnail((160, 160), Image.Resampling.LANCZOS)
brand.save(ASSETS / 'brand.png', optimize=True)
