# KOReader User Patches

A collection of user patches for [KOReader](https://github.com/koreader/koreader) that enhance the reading experience with richer statistics and frontlight controls.

---

## Patches

### 🌙 Frontlight Widget — Night Mode Toggle
**`2-frontlight-widget-nightmode.lua`**

<img width="384" height="512" alt="kép" src="https://github.com/user-attachments/assets/2401c194-0ae3-4c6e-8b7f-1c7c79f9a10d" />

Adds a **Night Mode** toggle button directly to the bottom of the built-in frontlight widget. Toggle inverts the screen and persists the setting — no need to dig through menus.

---

### 📊 Reading Insights
**`2-reading-insights-stats.lua`**

<img width="384" height="512" alt="kép" src="https://github.com/user-attachments/assets/c0669dbe-5e8e-4b40-a3c7-5299036e477b" />

A full-screen scrollable overlay with a comprehensive overview of your reading history, powered by KOReader's statistics database.

**Highlights:**
- **Today** — reading time and pages read so far today
- **Last week** — 7-day average time and pages per day
- **Streaks** — current and best daily & weekly reading streaks
- **Yearly view** — hours or days read + pages, navigable by year
- **Monthly chart** — bar chart of reading activity per month (tappable to see books)
- **All-time totals** — cumulative hours and pages across all years

**Controls:** swipe left/right to change year, tap bars to open book lists, tap the chart header to toggle hours/days mode, long-press to force-reload data.

**Caching:** uses a stale-while-revalidate strategy — the popup opens instantly with cached data while fresh values load in the background.

**Localization:** includes built-in English and Hungarian translations; additional languages can be added in the `PATCH_L10N` table.

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

<img width="384" height="512" alt="IMG_1920" src="https://github.com/user-attachments/assets/44ac91eb-dfbe-41cc-a26e-f4df06ffd3df" />


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
