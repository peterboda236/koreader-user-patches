# KOReader User Patches

A collection of user patches for [KOReader](https://github.com/koreader/koreader) that enhance the reading experience with richer statistics and frontlight controls.

---

## Patches

### 🌙 Frontlight Widget — Night Mode Toggle
**`2-frontlight-widget-nightmode.lua`**

<img width="384" height="512" alt="FileManager_2026-06-30_074755" src="https://github.com/user-attachments/assets/8ef06f58-e241-42ca-b4c4-a196b02f662b" />


Adds a **Night Mode** toggle button directly to the bottom of the built-in frontlight widget. Toggle inverts the screen and persists the setting — no need to dig through menus.

---

### 📊 Reading Insights - Patch moved to plugin
**`2-reading-insights-stats.lua`**
Plugin can be downloaded from here: https://github.com/peterboda236/readinginsights.koplugin

---

### 📖 Reading Stats Popup
**`2-reading-stats-popup.lua`**

<img width="384" height="512" alt="kép" src="https://github.com/user-attachments/assets/5f951bc0-a50a-416a-91dc-bb63a43f14ea" />

A compact overlay displayed while reading, showing live statistics for the current book.

**Highlights:**
- **This chapter / Next chapter** — estimated time left in the current chapter and time to read the next one
- **This book** — overall progress percentage, pages read, time spent, and time remaining
- **Chapter bar** — visual bar chart of all chapters, proportional to their length, with read/unread/current state; swipeable when there are many chapters
- **Pace** — today's reading time and pages-per-minute rate

**Controls:** tap anywhere to dismiss, swipe left/right to navigate the chapter bar.

---


### 📑 TOC Reading Time

**`2-toc-reading-time.lua`**

<img width="384" height="512" alt="Reader_Az Elso Torveny vilaga 1  - Hidegen talalva - Abercrombie, Joe #p(878) epub_p456_2026-06-30_074806" src="https://github.com/user-attachments/assets/fca94799-7197-4f54-a3ef-e3d1ddc6a722" />

Enriches the table of contents with an estimated reading time for each chapter, displayed alongside the existing page count.

1. Chapter  (41) ........................ 8

becomes:

1. Chapter  (41 | 00:44) ........................ 8

Can Enable/Disable in Reader mode / Settings.

Falls back to the original format if the Statistics plugin has no speed data yet (e.g. at the very start of a book).

Requirements: the Statistics plugin must be active and "Show chapter length" must be enabled in the TOC settings.

---

## Installation

Place the `.lua` files into KOReader's `patches` folder on your device:

```
<koreader_dir>/patches/
```

Restart KOReader. Patches prefixed with `2-` are applied after the UI initializes.

---

## Credits

Inspired by and based in part on patches by [@quanganhdo](https://github.com/quanganhdo/koreader-user-patches).
