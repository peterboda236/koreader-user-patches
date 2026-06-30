-- Appends estimated reading time to TOC entries:
--   "Chapter (41) ... 8"  ->  "Chapter (41 | 00:44) ... 8"
-- Falls back to original if Statistics plugin has no data yet.
-- Adds a toggle "Show chapter time" right next to "Show chapter length"
-- in the main reader menu (Settings -> ToC settings).
-- Version 1.1

local ReaderToc = require("apps/reader/modules/readertoc")
local reader_menu_order = require("ui/elements/reader_menu_order")
local _ = require("gettext")

-- --- simple manual i18n (en / hu) ---
local function T(en, hu)
    local lang = G_reader_settings:readSetting("language") or "en"
    if lang:match("^hu") then
        return hu
    end
    return en
end

-- default: on
if G_reader_settings:hasNot("toc_items_show_chapter_time") then
    G_reader_settings:saveSetting("toc_items_show_chapter_time", true)
end

local orig_completeTocWithChapterLengths = ReaderToc.completeTocWithChapterLengths
local orig_completeTocWithChapterLengthsFromPagemap = ReaderToc.completeTocWithChapterLengthsFromPagemap

local function injectTime(self)
    if not G_reader_settings:isTrue("toc_items_show_chapter_time") then return end
    local stats = self.ui and self.ui.statistics
    if not stats or not self.toc then return end
    for _, v in ipairs(self.toc) do
        if v.chapter_length and v.chapter_length > 0 then
            local time_str = stats:getTimeForPages(v.chapter_length)
            if time_str and time_str ~= "" then
                v.chapter_length = tostring(v.chapter_length) .. " | " .. time_str
            end
        end
    end
end

function ReaderToc:completeTocWithChapterLengths()
    orig_completeTocWithChapterLengths(self)
    injectTime(self)
end
function ReaderToc:completeTocWithChapterLengthsFromPagemap()
    orig_completeTocWithChapterLengthsFromPagemap(self)
    injectTime(self)
end

-- --- register new menu item ---
local orig_addToMainMenu = ReaderToc.addToMainMenu
function ReaderToc:addToMainMenu(menu_items)
    orig_addToMainMenu(self, menu_items)

    menu_items.toc_items_show_chapter_time = {
        text = T("Show chapter time", "Mutassa a fejezet idejét"),
        keep_menu_open = true,
        help_text = T(
            "Shows the estimated reading time for each chapter in the table of contents, based on your reading statistics. Requires 'Show chapter length' to be enabled as well.",
            "Megjeleníti az egyes fejezetek becsült olvasási idejét a tartalomjegyzékben, az olvasási statisztikák alapján. Ehhez a 'Mutassa a fejezet hosszát' opciónak is bekapcsolva kell lennie."
        ),
        enabled_func = function()
            return not G_reader_settings:nilOrFalse("toc_items_show_chapter_length")
        end,
        checked_func = function()
            if G_reader_settings:nilOrFalse("toc_items_show_chapter_length") then
                return false
            end
            return G_reader_settings:isTrue("toc_items_show_chapter_time")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("toc_items_show_chapter_time")
            self.toc_menu_items_built = false
        end,
    }
end

-- --- patch the menu order so our item shows up right after "toc_items_show_chapter_length" ---
local navi_settings = reader_menu_order.navi_settings
if navi_settings then
    local already_present = false
    for _, key in ipairs(navi_settings) do
        if key == "toc_items_show_chapter_time" then
            already_present = true
            break
        end
    end
    if not already_present then
        for i, key in ipairs(navi_settings) do
            if key == "toc_items_show_chapter_length" then
                table.insert(navi_settings, i + 1, "toc_items_show_chapter_time")
                break
            end
        end
    end
end
