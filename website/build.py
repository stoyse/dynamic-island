#!/usr/bin/env python3
"""Build a fully self-contained website/index.html from index.template.html.

Inlines every image (favicon + <img>) as a base64 data URI so the page is a
single portable file with zero external asset requests — ideal for a static
deploy. The og:/twitter: image stays an absolute URL (social crawlers can't
read data URIs), so assets/hero.png is kept alongside for that.
"""
import base64, mimetypes, pathlib, re

HERE = pathlib.Path(__file__).parent
OG_BASE = "https://dynamic-island.stosse.group"  # absolute base for social cards

def data_uri(rel: str) -> str:
    p = HERE / rel
    mime = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
    b64 = base64.b64encode(p.read_bytes()).decode()
    return f"data:{mime};base64,{b64}"

html = (HERE / "index.template.html").read_text()

# 1) inline favicon + every <img src="assets/..."> / href="assets/...">
for rel in ["assets/icon.png", "assets/demo.gif", "assets/hero.png"]:
    uri = data_uri(rel)
    html = html.replace(f'src="{rel}"', f'src="{uri}"')
    html = html.replace(f'href="{rel}"', f'href="{uri}"')

# 2) keep social-card images as absolute, fetchable URLs (not data URIs)
html = html.replace('content="assets/hero.png"', f'content="{OG_BASE}/assets/hero.png"')

out = HERE / "index.html"
out.write_text(html)

remaining = len(re.findall(r'(?:src|href)="assets/', html))
print(f"wrote {out}  ({out.stat().st_size/1024:.0f} KB, {remaining} external asset refs left)")
