# Regenerating the App Store screenshots

The screenshots are rendered from HTML mock-ups of the v2 screens (no Apple trademarks in the copy).

```bash
cd AppStore/Design/src
cp ../../AppIcon-1024.png icon.png
python3 gen.py en && python3 gen.py vi             # → en-*.html, vi-*.html
node render.js en-*.html vi-*.html                  # → 2880 × 1800 PNGs (needs Playwright + Inter font)
python3 store.py en && python3 store.py vi && node rstore.js store-en.html store-vi.html
```

Copy the PNGs to `AppStore/Screenshots/{en-US,vi}`. Once v2 runs on a Mac, real captures of the
app can replace the window area.
