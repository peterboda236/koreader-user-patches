-- Appends estimated reading time to TOC entries:
--   "Chapter (41) ... 8"  ->  "Chapter (41 | 00:44) ... 8"
-- Falls back to original if Statistics plugin has no data yet.

local ReaderToc = require("apps/reader/modules/readertoc")

local orig_completeTocWithChapterLengths = ReaderToc.completeTocWithChapterLengths
local orig_completeTocWithChapterLengthsFromPagemap = ReaderToc.completeTocWithChapterLengthsFromPagemap

local function injectTime(self)
    local stats = self.ui and self.ui.statistics
    if not stats or not self.toc then return end
    for _, v in ipairs(self.toc) do
        if v.chapter_length and v.chapter_length > 0 then
            local time_str = stats:getTimeForPages(v.chapter_length)
            if time_str and time_str ~= "" then
                -- T("(%1)", chapter_length) uses gsub which needs a string/number,
                -- so we replace chapter_length with a string "41 | 00:44"
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
