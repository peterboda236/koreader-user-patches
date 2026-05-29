--[[
Reading Insights Popup
Version: 1.0.0
Based on:  https://github.com/quanganhdo/koreader-user-patches/blob/main/2-reading-insights-popup.lua

Full-screen scrollable overlay that displays an overview of reading history
queried from KOReader's statistics SQLite database (statistics.sqlite3).

Sections shown:
  - Today          reading time and pages read today
  - Last week      7-day average time and pages per day
  - Current/Best   daily and weekly reading streaks
  - Year           hours or days read + pages, navigable by year
  - Monthly chart  bar chart of hours or days read per month (tappable)
  - Total read     all-time hours and pages across all years

Controls:
  - Any key          dismiss
  - Prev/Next key    navigate to previous/next year
  - Swipe left/right change year
  - Swipe down       close
  - Tap left yearly value or monthly bar  open book list for that period
  - Tap monthly chart header              toggle hours/days mode
  - Long press anywhere                   force-reload all data from DB

Caching:
  Streaks and year range are cached per day; today stats per minute; yearly
  and monthly stats per year per day. A stale-while-revalidate strategy is
  used so the popup always opens immediately with the last known data while
  fresh values are loaded in the background.
]]--

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderUI = require("apps/reader/readerui")
local Size = require("ui/size")
local SQ3 = require("lua-ljsqlite3/init")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen
local gettext = require("gettext")
local T = require("ffi/util").template
local util = require("util")

-- Set to false to disable all caching (every popup open will query the DB fresh).
-- Set to true to cache results: streaks/year_range per day, today stats per minute,
-- yearly and monthly stats per year per day.
local ENABLE_CACHE = true

-- Set to true to trigger a full-screen ("flash") refresh on popup open and close.
-- Set to false to use the default partial ("ui") refresh only.
local FULL_SCREEN_REFRESH_ON_OPEN_CLOSE = true

local _cache = {
    streaks      = nil,
    streaks_date = nil,
    today        = nil,
    today_minute = nil,
    year_range      = nil,
    year_range_date = nil,
    all_time      = nil,
    all_time_date = nil,
    last_week        = nil,
    last_week_minute = nil,
}
local _yearly_cache  = {}
local _monthly_cache = {}

-- Stale-while-revalidate: when the cache has expired, the previous (stale)
-- values are kept in a separate table for immediate display on the next open.
-- _stale_cache is read-only inside init(); all writes go to the primary
-- _cache / _yearly_cache / _monthly_cache tables.
local _stale_cache   = {}
local _stale_yearly  = {}
local _stale_monthly = {}

local function clearAllCache()
    _cache.streaks         = nil
    _cache.streaks_date    = nil
    _cache.today           = nil
    _cache.today_minute    = nil
    _cache.year_range      = nil
    _cache.year_range_date = nil
    _cache.all_time        = nil
    _cache.all_time_date   = nil
    _cache.last_week        = nil
    _cache.last_week_minute = nil
    _yearly_cache          = {}
    _monthly_cache         = {}
    -- Stale cache is also wiped on explicit force-reload (long press)
    _stale_cache           = {}
    _stale_yearly          = {}
    _stale_monthly         = {}
end

local function todayDateStr()
    return os.date("%Y-%m-%d")
end

local function currentMinute()
    return math.floor(os.time() / 60)
end

-- User patch localization: add your language overrides here.
local PATCH_L10N = {
    en = {
        ["Jan"] = "Jan",
        ["Feb"] = "Feb",
        ["Mar"] = "Mar",
        ["Apr"] = "Apr",
        ["May"] = "May",
        ["Jun"] = "Jun",
        ["Jul"] = "Jul",
        ["Aug"] = "Aug",
        ["Sep"] = "Sep",
        ["Oct"] = "Oct",
        ["Nov"] = "Nov",
        ["Dec"] = "Dec",
        ["January"] = "January",
        ["February"] = "February",
        ["March"] = "March",
        ["April"] = "April",
        ["May "] = "May",
        ["June"] = "June",
        ["July"] = "July",
        ["August"] = "August",
        ["September"] = "September",
        ["October"] = "October",
        ["November"] = "November",
        ["December"] = "December",
        ["second read"] = "second read",
        ["seconds read"] = "seconds read",
        ["minute read"] = "minute read",
        ["minutes read"] = "minutes read",
        ["hour read"] = "hour read",
        ["hours read"] = "hours read",
        ["day read"] = "day read",
        ["days read"] = "days read",
        ["page read"] = "page read",
        ["pages read"] = "pages read",
        ["week in a row"] = "week in a row",
        ["weeks in a row"] = "weeks in a row",
        ["day in a row"] = "day in a row",
        ["days in a row"] = "days in a row",
        ["page"] = "page",
        ["pages"] = "pages",
        ["TODAY"] = "Today",
        ["No weekly streak"] = "No weekly streak",
        ["No daily streak"] = "No daily streak",
        ["CURRENT STREAK"] = "Current streak",
        ["BEST STREAK"] = "Best streak",
        ["DAYS READ PER MONTH"] = "Days read per month",
        ["HOURS READ PER MONTH"] = "Hours read per month",
        ["Reading statistics: reading insights"] = "Reading statistics: reading insights",
        ["Unknown"] = "Unknown",
        ["No books read"] = "No books read",
        ["No books read in %1"] = "No books read in %1",
        ["No books read in "] = "No books read in ",
        ["%1 - Book Read (%2)"] = "%1 - Book Read (%2)",
        ["%1 - Books Read (%2)"] = "%1 - Books Read (%2)",
        ["%1 - book read (%2)"] = "%1 - book read (%2)",
        ["%1 - books read (%2)"] = "%1 - books read (%2)",
        ["Reloading data..."] = "Reloading data...",
        ["book started"] = "book started",
        ["books started"] = "books started",
        ["Reading insights"] = "Reading insights",
        ["ALL BOOKS READ"] = "All books read",
        ["TOTAL READ"] = "Total read",
        ["LAST WEEK"] = "Last week",
        ["avg/day"] = "avg/day",
    },
    hu = {
        ["Jan"] = "Jan",
        ["Feb"] = "Febr",
        ["Mar"] = "Márc",
        ["Apr"] = "Ápr",
        ["May"] = "Máj",
        ["Jun"] = "Jún",
        ["Jul"] = "Júl",
        ["Aug"] = "Aug",
        ["Sep"] = "Szept",
        ["Oct"] = "Okt",
        ["Nov"] = "Nov",
        ["Dec"] = "Dec",
        ["January"] = "Január",
        ["February"] = "Február",
        ["March"] = "Március",
        ["April"] = "Április",
        ["May "] = "Május",
        ["June"] = "Június",
        ["July"] = "Július",
        ["August"] = "Augusztus",
        ["September"] = "Szeptember",
        ["October"] = "Október",
        ["November"] = "November",
        ["December"] = "December",
        ["second read"] = "olvasott mp",
        ["seconds read"] = "olvasott mp",
        ["minute read"] = "olvasott perc",
        ["minutes read"] = "olvasott perc",
        ["hour read"] = "olvasott óra",
        ["hours read"] = "olvasott óra",
        ["day read"] = "olvasással töltött nap",
        ["days read"] = "olvasással töltött nap",
        ["page read"] = "olvasott oldal",
        ["pages read"] = "olvasott oldal",
        ["week in a row"] = "egymást követő hét",
        ["weeks in a row"] = "egymást követő hét",
        ["day in a row"] = "egymást követő nap",
        ["days in a row"] = "egymást követő nap",
        ["page"] = "oldal",
        ["pages"] = "oldal",
        ["TODAY"] = "Mai nap",
        ["No weekly streak"] = "Nincs heti széria",
        ["No daily streak"] = "Nincs napi széria",
        ["CURRENT STREAK"] = "Aktuális széria",
        ["BEST STREAK"] = "Legjobb széria",
        ["DAYS READ PER MONTH"] = "Havonta olvasott napok",
        ["HOURS READ PER MONTH"] = "Havonta olvasott órák",
        ["Reading statistics: reading insights"] = "Olvasási statisztika: olvasási betekintés",
        ["Unknown"] = "Ismeretlen",
        ["No books read"] = "Nincs elolvasott könyv",
        ["No books read in %1"] = "Nincs elolvasott könyv: %1",
        ["No books read in "] = "Nincs elolvasott könyv: ",
        ["%1 - Book Read (%2)"] = "%1 - könyv elolvasva (%2)",
        ["%1 - Books Read (%2)"] = "%1 - könyv elolvasva (%2)",
        ["%1 - book read (%2)"] = "%1 - olvasott könyv (%2)",
        ["%1 - books read (%2)"] = "%1 - olvasott könyvek (%2)",
        ["Reloading data..."] = "Adatok újraolvasása...",
        ["book started"] = "elkezdett könyv",
        ["books started"] = "elkezdett könyv",
        ["Reading insights"] = "Olvasási betekintés",
        ["ALL BOOKS READ"] = "Összes olvasott könyvek",
        ["TOTAL READ"] = "Összes olvasás",
        ["LAST WEEK"] = "Legutóbbi hét",
        ["avg/day"] = "átl./nap",
    },
}

local function l10nLookup(msg)
    local lang = "en"
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or "en"
    end
    local lang_base = lang:match("^([a-z]+)") or lang
    local map = PATCH_L10N[lang] or PATCH_L10N[lang_base] or PATCH_L10N.en or {}
    return map[msg]
end

local function _(msg)
    return l10nLookup(msg) or gettext(msg)
end

local function N_(singular, plural, n)
    local singular_override = l10nLookup(singular)
    local plural_override = l10nLookup(plural)
    if singular_override or plural_override then
        if n == 1 then
            return singular_override or plural_override
        end
        return plural_override or singular_override
    end
    return gettext.ngettext(singular, plural, n)
end

-- Cached language base code (e.g. "hu", "en") — read once per session.
local _cached_lang_base = nil
local function getLangBase()
    if not _cached_lang_base then
        local lang = "en"
        if G_reader_settings and G_reader_settings.readSetting then
            lang = G_reader_settings:readSetting("language") or "en"
        end
        _cached_lang_base = lang:match("^([a-z]+)") or lang
    end
    return _cached_lang_base
end

-- HU: space thousands separator, comma decimal; EN: comma thousands separator, period decimal.
-- Fast path for small integers (< 10 000, no decimals) skips regex.
local function formatNumber(n, decimals)
    if n == nil then return "" end
    decimals = decimals or 0
    local is_hu = (getLangBase() == "hu")
    if decimals == 0 and n >= 0 and n < 10000 then
        return tostring(math.floor(n))
    end
    local s = string.format("%." .. decimals .. "f", n)
    local int, frac = s:match("^(%-?%d+)%.*(%d*)$")
    if not int then return s end
    local absInt = int:gsub("^%-", "")
    local threshold = is_hu and 5 or 4  -- HU: from 10 000 (5 digits); EN: from 1,000 (4 digits)
    if #absInt >= threshold then
        if is_hu then
            int = int:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
        else
            int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        end
    end
    if frac ~= "" then return int .. (is_hu and "," or ".") .. frac end
    return int
end

local function formatCount(value)
    if value == nil then return "" end
    if type(value) == "number" then return formatNumber(value, 0) end
    return tostring(value)
end

local MONTH_NAMES_SHORT = {
    _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"),
    _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec"),
}
local MONTH_NAMES_FULL = {
    _("January"), _("February"), _("March"), _("April"), _("May "), _("June"),
    _("July"), _("August"), _("September"), _("October"), _("November"), _("December"),
}

local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local ReadingInsightsPopup

local INSIGHTS_MODE_KEY = "reading_insights_popup_mode"
local INSIGHTS_MODE_DAYS = "days"
local INSIGHTS_MODE_HOURS = "hours"

local function normalizeInsightsMode(mode)
    if mode == INSIGHTS_MODE_DAYS then
        return INSIGHTS_MODE_DAYS
    end
    -- default: hours
    return INSIGHTS_MODE_HOURS
end

local function readInsightsMode()
    if G_reader_settings and G_reader_settings.readSetting then
        return normalizeInsightsMode(G_reader_settings:readSetting(INSIGHTS_MODE_KEY, INSIGHTS_MODE_HOURS))
    end
    return INSIGHTS_MODE_HOURS
end

local function saveInsightsMode(mode)
    if G_reader_settings and G_reader_settings.saveSetting then
        G_reader_settings:saveSetting(INSIGHTS_MODE_KEY, mode)
    end
end

local function withStatsDb(fallback, fn)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(db_path, "mode") ~= "file" then
        return fallback
    end

    local conn = SQ3.open(db_path)
    if not conn then return fallback end

    local ok, result = pcall(fn, conn)
    conn:close()
    if ok then
        return result
    end
    return fallback
end

local function withStatement(conn, sql, fn)
    local stmt = conn:prepare(sql)
    if not stmt then return end
    local ok, result = pcall(fn, stmt)
    stmt:close()
    if ok then
        return result
    end
end

local function computeStreaks(entries_desc, is_consecutive, is_current_start)
    if #entries_desc == 0 then
        return 0, 0
    end

    local current = 0
    if is_current_start(entries_desc[1]) then
        current = 1
        for i = 2, #entries_desc do
            if is_consecutive(entries_desc[i - 1], entries_desc[i]) then
                current = current + 1
            else
                break
            end
        end
    end

    local best = 1
    local run = 1
    for i = 2, #entries_desc do
        if is_consecutive(entries_desc[i - 1], entries_desc[i]) then
            run = run + 1
            if run > best then
                best = run
            end
        else
            run = 1
        end
    end

    return current, best
end

local function parseDateYMD(date_str)
    if not date_str then return end
    local year = tonumber(date_str:sub(1,4))
    local month = tonumber(date_str:sub(6,7))
    local day = tonumber(date_str:sub(9,10))
    if not year or not month or not day then return end
    return year, month, day
end

local function parseWeekYear(week_str)
    if not week_str then return end
    local year_str, week_str_num = week_str:match("(%d+)-(%d+)")
    local year = tonumber(year_str)
    local week = tonumber(week_str_num)
    if not year or week == nil then return end
    return year, week
end

local Math = require("optmath")

local function formatTimeRead(seconds)
    if not seconds or seconds <= 0 then
        return "", ""
    end
    
    if seconds < 60 then
        local s = Math.round(seconds)  -- Math.round instead of math.floor
        return formatNumber(s, 0),
               N_("second read", "seconds read", s)

    elseif seconds < 3600 then
        local m = Math.round(seconds / 60)
        return formatNumber(m, 0),
               N_("minute read", "minutes read", m)

    else
        local rounded_minutes = Math.round(seconds / 60)
        local h = math.floor(rounded_minutes / 60 * 10) / 10
        return formatNumber(h, 1),
               N_("hour read", "hours read", h)
    end
end

local function formatHoursRead(seconds)
    if not seconds or seconds <= 0 then
        return "0", N_("hour read", "hours read", 0)
    end

    local rounded_minutes = Math.round(seconds / 60)
    local h = math.floor(rounded_minutes / 60 * 10) / 10
    h = math.floor(h)  -- drop decimal
    return formatNumber(h, 0),
           N_("hour read", "hours read", h)
end

-- HH:MM:SS format for book list entries (e.g. 00:10:10)
local function formatHHMMSS(seconds)
    if not seconds or seconds <= 0 then return "00:00:00" end
    local s = math.floor(seconds)
    local hh = math.floor(s / 3600)
    local mm = math.floor((s % 3600) / 60)
    local ss = s % 60
    return string.format("%02d:%02d:%02d", hh, mm, ss)
end

local function getSerifFace(font_name, fallback_name, size)
    return Font:getFace(font_name, size) or Font:getFace(fallback_name, size)
end

local function buildSerifFonts()
    return {
        section = getSerifFace("NotoSans-Bold.ttf", "tfont", 20),
        value   = getSerifFace("NotoSans-Bold.ttf",    "tfont", 28),
        label   = getSerifFace("NotoSans-Regular.ttf", "x_smallinfofont", 18),
        small   = getSerifFace("NotoSans-Regular.ttf", "xx_smallinfofont", 16),

    }

end

local function buildLayout(screen_w, padding_h, column_gap)
    local separator_width = 2 * column_gap + Size.line.medium
    local content_width = screen_w - 2 * padding_h
    local col_width = math.floor((content_width - separator_width) / 2)
    return {
        full_width    = screen_w,
        padding_h     = padding_h,
        column_gap    = column_gap,
        separator_width = separator_width,
        content_width = content_width,
        col_width     = col_width,
    }
end

local function buildColumnSeparator(column_gap, height)
    local v_padding = Size.padding.default
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = column_gap },
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ height = v_padding },
            LineWidget:new{
                dimen = Geom:new{ w = Size.line.medium, h = height - 2 * v_padding },
                background = Blitbuffer.COLOR_GRAY,
            },
            VerticalSpan:new{ height = v_padding },
        },
        HorizontalSpan:new{ width = column_gap },
    }
end

local function buildSectionHeader(font_section, text, width, left_padding)
    left_padding = left_padding or Size.padding.large
    local text_widget = TextWidget:new{ text = text, face = font_section }
    return FrameContainer:new{
        background    = Blitbuffer.COLOR_WHITE,
        bordersize    = 0,
        padding_top   = Size.padding.small,
        padding_bottom = Size.padding.small,
        padding_left  = left_padding,
        padding_right = 0,
        LeftContainer:new{
            dimen = Geom:new{ w = width - left_padding, h = text_widget:getSize().h },
            text_widget,
        },
    }
    
end

local function buildValueLine(font_value, font_label, col_width, value, unit)
    if value == "" then
        return TextBoxWidget:new{
            text      = unit,
            face      = font_label,
            width     = col_width,
            alignment = "left",
        }
    end

    local value_widget = TextWidget:new{ text = value, face = font_value }
    local value_width = value_widget:getSize().w
    local text_desc_width = col_width - value_width - Size.padding.large
    return HorizontalGroup:new{
        align = "center",
        value_widget,
        HorizontalSpan:new{ width = Size.padding.large },
        TextBoxWidget:new{
            text      = unit,
            face      = font_label,
            width     = text_desc_width,
            alignment = "left",
        },
    }
end

local function fixedCol(widget, width)
    return LeftContainer:new{
        dimen  = Geom:new{ w = width, h = widget:getSize().h },
        widget,
    }
end

local function padded(padding_h, widget)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = padding_h },
        widget,
    }
end

local function buildTwoColRow(left_widget, right_widget, layout)
    return HorizontalGroup:new{
        align = "center",
        fixedCol(left_widget, layout.col_width),
        buildColumnSeparator(layout.column_gap, left_widget:getSize().h),
        fixedCol(right_widget, layout.col_width),
    }
end

local function addSectionWithRow(sections, header_widget, row, layout, opts)
    local pad_row        = true
    local add_divider    = true
    local no_bottom_line = false
    local no_top_line    = false
    if opts then
        if opts.pad_row        == false then pad_row        = false end
        if opts.add_divider    == false then add_divider    = false end
        if opts.no_bottom_line == true  then no_bottom_line = true  end
        if opts.no_top_line    == true  then no_top_line    = true  end
    end

    table.insert(sections, header_widget)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.default })
    if add_divider and not no_top_line then
        table.insert(sections, padded(layout.padding_h, LineWidget:new{
            dimen      = Geom:new{ w = layout.content_width, h = Size.line.thin },
            background = Blitbuffer.COLOR_GRAY,
        }))
    end
    table.insert(sections, pad_row and padded(layout.padding_h, row) or row)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.large })
    if add_divider and not no_bottom_line then
        table.insert(sections, padded(layout.padding_h, LineWidget:new{
            dimen      = Geom:new{ w = layout.content_width, h = Size.line.thick },
            background = Blitbuffer.COLOR_GRAY,
        }))
    end
end

local function buildYearHeader(font_section, layout, year_range, selected_year)
    local prev_available = selected_year > year_range.min_year
    local next_available = selected_year < year_range.max_year

    local inner_pad = Size.padding.default
    local gap       = Size.padding.small

    local sample_arrow = TextWidget:new{ text = "\xe2\x80\xb9", face = font_section }
    local arrow_w = sample_arrow:getSize().w
    sample_arrow:free()

    local sample_yr = TextWidget:new{ text = tostring(selected_year - 1), face = font_section }
    local yr_side_w = sample_yr:getSize().w
    sample_yr:free()

    local slot_w = arrow_w + gap + yr_side_w + inner_pad

    local year_label = TextWidget:new{
        text = tostring(selected_year),
        face = font_section,
    }

    local function makeSlot(yr, arrow_glyph, left, visible)
        if not visible then
            return HorizontalSpan:new{ width = slot_w }, slot_w
        end

        local arrow_tw = TextWidget:new{
            text    = arrow_glyph,
            face    = font_section,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local yr_tw = TextWidget:new{
            text    = tostring(yr),
            face    = font_section,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local parts
        if left then
            parts = HorizontalGroup:new{
                align = "center",
                arrow_tw,
                HorizontalSpan:new{ width = gap },
                yr_tw,
                HorizontalSpan:new{ width = inner_pad },
            }
        else
            parts = HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = inner_pad },
                yr_tw,
                HorizontalSpan:new{ width = gap },
                arrow_tw,
            }
        end
        return parts, slot_w
    end

    local left_slot,  left_w  = makeSlot(selected_year - 1, "\xe2\x80\xb9", true,  prev_available)
    local right_slot, right_w = makeSlot(selected_year + 1, "\xe2\x80\xba", false, next_available)

    local year_w    = year_label:getSize().w
    local remaining = layout.content_width - left_w - right_w - year_w
    if remaining < 0 then remaining = 0 end
    local side_l = math.floor(remaining / 2)
    local side_r = remaining - side_l

    local header_content = HorizontalGroup:new{
        align = "center",
        left_slot,
        HorizontalSpan:new{ width = side_l },
        year_label,
        HorizontalSpan:new{ width = side_r },
        right_slot,
    }

    return FrameContainer:new{
        background     = Blitbuffer.COLOR_WHITE,
        bordersize     = 0,
        padding_top    = Size.padding.small,
        padding_bottom = Size.padding.small,
        padding_left   = layout.padding_h,
        padding_right  = layout.padding_h,
        header_content,
    }
end

local function buildYearlyRow(popup_self, yearly_stats, fonts, layout)
    local left_value = ""
    local left_unit  = ""
    if popup_self.mode == INSIGHTS_MODE_HOURS then
        left_value, left_unit = formatHoursRead(yearly_stats.duration)
    else
        left_value = formatCount(yearly_stats.days)
        left_unit  = N_("day read", "days read", yearly_stats.days)
    end
    local left_line = buildValueLine(
        fonts.value, fonts.label, layout.col_width, left_value, left_unit)
    local pages_val = buildValueLine(
        fonts.value, fonts.label, layout.col_width,
        formatCount(yearly_stats.pages),
        N_("page read", "pages read", yearly_stats.pages))

    local selected_year_for_tap = popup_self.selected_year

    local left_cell = InputContainer:new{
        dimen = Geom:new{ w = layout.col_width, h = left_line:getSize().h },
        left_line,
    }
    left_cell.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return left_cell.dimen end } },
    }
    function left_cell:onTap()
        popup_self:showBooksForYear(selected_year_for_tap)
        return true
    end

    local right_cell = InputContainer:new{
        dimen = Geom:new{ w = layout.col_width, h = pages_val:getSize().h },
        pages_val,
    }
    right_cell.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return right_cell.dimen end } },
    }
    function right_cell:onTap()
        popup_self:showBooksForYear(selected_year_for_tap)
        return true
    end

    local yearly_row = buildTwoColRow(left_cell, right_cell, layout)

    return VerticalGroup:new{
        align = "left",
        FrameContainer:new{
            bordersize = 0,
            padding    = 0,
            padded(layout.padding_h, yearly_row),
        },
    }
end

local function buildMonthlyChart(popup_self, monthly_data, layout, fonts)
    if #monthly_data == 0 then return nil end

    local value_key = (popup_self.mode == INSIGHTS_MODE_HOURS and "hours") or "days"
    local max_value = 1
    for _, m in ipairs(monthly_data) do
        local v = tonumber(m[value_key]) or 0
        if v > max_value then max_value = v end
    end

    local chart_width  = layout.content_width
    local bar_height   = tonumber(Screen:scaleBySize(46))
    local bar_width    = math.floor(chart_width / 6) - tonumber(Screen:scaleBySize(8))
    local bar_gap      = math.floor((chart_width - bar_width * 6) / 5)
    local font_small   = fonts.small

    local sample_label = TextWidget:new{ text = "0", face = font_small }
    local label_height = sample_label:getSize().h
    sample_label:free()

    local current_year  = tonumber(os.date("%Y"))
    local current_month = os.date("%Y-%m")

    local function createBarRow(data_slice)
        local bars_row        = HorizontalGroup:new{ align = "bottom" }
        local month_labels_row = HorizontalGroup:new{ align = "top" }
        local baseline_h      = Size.line.medium
        local total_bar_height = bar_height + label_height

        for i, m in ipairs(data_slice) do
            local value = tonumber(m[value_key]) or 0
            local ratio = max_value > 0 and (value / max_value) or 0
            local bar_h = math.floor(ratio * bar_height + 0.5)
            if bar_h == 0 and value > 0 then bar_h = 1 end

            local is_current = (popup_self.selected_year == current_year) and (m.month == current_month)
            local bar_color  = is_current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY

            local value_label   = TextWidget:new{ text = formatNumber(value), face = font_small }
            local centered_label = CenterContainer:new{
                dimen  = Geom:new{ w = bar_width, h = label_height },
                value_label,
            }

            local bar_column = VerticalGroup:new{ align = "center" }
            table.insert(bar_column, centered_label)
            if bar_h > 0 then
                table.insert(bar_column, LineWidget:new{
                    dimen      = Geom:new{ w = bar_width, h = bar_h },
                    background = bar_color,
                })
            end
            table.insert(bar_column, LineWidget:new{
                dimen      = Geom:new{ w = bar_width, h = baseline_h },
                background = bar_color,
            })

            local bar_container = BottomContainer:new{
                dimen = Geom:new{ w = bar_width, h = total_bar_height },
                bar_column,
            }

            local tappable_bar = InputContainer:new{
                dimen = Geom:new{ w = bar_width, h = total_bar_height },
                bar_container,
            }
            local month_data       = m
            local month_year_label = m.label_full .. " " .. popup_self.selected_year
            tappable_bar.ges_events = {
                Tap = { GestureRange:new{ ges = "tap", range = function() return tappable_bar.dimen end } },
            }
            function tappable_bar:onTap()
                popup_self:showBooksForMonth(month_data.month, month_year_label)
                return true
            end

            table.insert(bars_row, tappable_bar)

            local month_label_widget = TextWidget:new{ text = m.label, face = font_small }
            table.insert(month_labels_row, CenterContainer:new{
                dimen = Geom:new{ w = bar_width, h = month_label_widget:getSize().h },
                month_label_widget,
            })

            if i < #data_slice then
                table.insert(bars_row,         HorizontalSpan:new{ width = bar_gap })
                table.insert(month_labels_row, HorizontalSpan:new{ width = bar_gap })
            end
        end

        return VerticalGroup:new{
            align = "center",
            bars_row,
            VerticalSpan:new{ height = Size.padding.small },
            month_labels_row,
        }
    end

    local chart     = VerticalGroup:new{ align = "center" }
    local row_index = 0
    for i = 1, #monthly_data, 6 do
        local row_data = {}
        for j = i, math.min(i + 5, #monthly_data) do
            table.insert(row_data, monthly_data[j])
        end
        if #row_data > 0 then
            if row_index > 0 then
                table.insert(chart, VerticalSpan:new{ height = Size.padding.default })
            end
            table.insert(chart, createBarRow(row_data))
            row_index = row_index + 1
        end
    end

    return chart
end

local function buildInsightsSections(popup_self, streaks, yearly_stats, year_range, monthly_data, today_stats, all_time_stats, last_week_stats, fonts, layout)
    local sections = VerticalGroup:new{ align = "left" }

    local has_today = today_stats and (today_stats.seconds > 0 or today_stats.pages > 0)

    -- Top thick line (currently unused)
 --   table.insert(sections, padded(layout.padding_h, LineWidget:new{
 --       dimen      = Geom:new{ w = layout.content_width, h = Size.line.thick },
 --       background = Blitbuffer.COLOR_GRAY,
 --   }))

    if has_today then
        local time_val, time_unit = formatTimeRead(today_stats.seconds)
        local pages_val  = today_stats.pages > 0 and formatCount(today_stats.pages) or ""
        local pages_unit = today_stats.pages > 0 and N_("page read", "pages read", today_stats.pages) or ""
        local today_row  = buildTwoColRow(
            buildValueLine(fonts.value, fonts.label, layout.col_width, time_val,  time_unit),
            buildValueLine(fonts.value, fonts.label, layout.col_width, pages_val, pages_unit),
            layout)

        local today_header_inner = buildSectionHeader(fonts.section, _("TODAY"), layout.full_width)
        local today_header = InputContainer:new{
            dimen = today_header_inner:getSize(),
            today_header_inner,
        }
        today_header.ges_events = {
            Hold = { GestureRange:new{ ges = "hold", range = function() return today_header.dimen end } },
        }
        function today_header:onHold()
            local msg = InfoMessage:new{ text = _("Reloading data...") }
            UIManager:show(msg)
            UIManager:scheduleIn(0.5, function()
                UIManager:close(msg)
                clearAllCache()
                popup_self._streaks  = nil
                popup_self._today    = nil
                popup_self._yearly   = nil
                popup_self._monthly  = nil
                popup_self._all_time = nil
                popup_self._last_week = nil
                popup_self:_loadAndRebuild()
            end)
            return true
        end

        addSectionWithRow(sections, today_header, today_row, layout)
    end

    -- LAST WEEK section
    do
        local lw = last_week_stats or { avg_seconds = 0, avg_pages = 0 }
        local has_week = lw.avg_seconds > 0 or lw.avg_pages > 0
        if has_week then
            -- Time cell: formatTimeRead on average seconds
            local week_time_val, week_time_unit = formatTimeRead(lw.avg_seconds)
            -- Append "avg/day" label to the unit string
            local week_time_unit_full = week_time_unit .. " " .. _("avg/day")

            -- Pages cell: rounded to one decimal when below 10, otherwise integer
            local avg_pages_rounded
            if lw.avg_pages >= 10 then
                avg_pages_rounded = math.floor(lw.avg_pages + 0.5)
            else
                avg_pages_rounded = math.floor(lw.avg_pages * 10 + 0.5) / 10
            end
            local week_pages_val  = formatNumber(avg_pages_rounded, avg_pages_rounded ~= math.floor(avg_pages_rounded) and 1 or 0)
            local week_pages_unit = N_("page read", "pages read", avg_pages_rounded) .. " " .. _("avg/day")

            local week_row = buildTwoColRow(
                buildValueLine(fonts.value, fonts.label, layout.col_width, week_time_val,   week_time_unit_full),
                buildValueLine(fonts.value, fonts.label, layout.col_width, week_pages_val,  week_pages_unit),
                layout)

            addSectionWithRow(sections,
                buildSectionHeader(fonts.section, _("LAST WEEK"), layout.full_width),
                week_row, layout)
        end
    end


    local function streakDisplay(n, unit_label, empty_label)
        if n < 2 then return "", empty_label end
        return formatCount(n), unit_label(n)
    end

    local cd_val, cd_unit = streakDisplay(streaks.current_days,
        function(n) return N_("day in a row",  "days in a row",  n) end, _("No daily streak"))
    local cw_val, cw_unit = streakDisplay(streaks.current_weeks,
        function(n) return N_("week in a row", "weeks in a row", n) end, _("No weekly streak"))
    local bd_val, bd_unit = streakDisplay(streaks.best_days,
        function(n) return N_("day in a row",  "days in a row",  n) end, _("No daily streak"))
    local bw_val, bw_unit = streakDisplay(streaks.best_weeks,
        function(n) return N_("week in a row", "weeks in a row", n) end, _("No weekly streak"))

    -- Combined header: CURRENT STREAK | BEST STREAK (two-column layout)
    -- left_padding=0 so the text aligns exactly to the col_width cells; padding_h is the outer margin
    local streak_header_left  = buildSectionHeader(fonts.section, _("CURRENT STREAK"), layout.col_width, 0)
    local streak_header_right = buildSectionHeader(fonts.section, _("BEST STREAK"),    layout.col_width, 0)
    local sep_h = streak_header_left:getSize().h
    local streak_combined_header = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding    = 0,
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = layout.padding_h },
            fixedCol(streak_header_left,  layout.col_width),
            buildColumnSeparator(layout.column_gap, sep_h),
            fixedCol(streak_header_right, layout.col_width),
        },
    }

    -- Row 1: consecutive DAYS (left = current, right = best)
    local days_row = buildTwoColRow(
        buildValueLine(fonts.value, fonts.label, layout.col_width, cd_val, cd_unit),
        buildValueLine(fonts.value, fonts.label, layout.col_width, bd_val, bd_unit),
        layout)
    -- Row 2: consecutive WEEKS (left = current, right = best)
    local weeks_row = buildTwoColRow(
        buildValueLine(fonts.value, fonts.label, layout.col_width, cw_val, cw_unit),
        buildValueLine(fonts.value, fonts.label, layout.col_width, bw_val, bw_unit),
        layout)

    local streak_rows = VerticalGroup:new{
        align = "left",
        FrameContainer:new{
            bordersize = 0,
            padding    = 0,
            padded(layout.padding_h, days_row),
        },
        VerticalSpan:new{ height = Size.padding.default },
        FrameContainer:new{
            bordersize = 0,
            padding    = 0,
            padded(layout.padding_h, weeks_row),
        },
    }

    -- The top divider line is always shown above the streak section (even when the TODAY section is hidden)
    addSectionWithRow(sections,
        streak_combined_header,
        streak_rows, layout, { pad_row = false })

    local year_header = buildYearHeader(fonts.section, layout, year_range, popup_self.selected_year)
    local yearly_row  = buildYearlyRow(popup_self, yearly_stats, fonts, layout)

    local chart = buildMonthlyChart(popup_self, monthly_data, layout, fonts)

    addSectionWithRow(sections, year_header, yearly_row, layout, { pad_row = false, no_bottom_line = not chart })

    if chart then
        local chart_header_text = (popup_self.mode == INSIGHTS_MODE_HOURS and _("HOURS READ PER MONTH"))
            or _("DAYS READ PER MONTH")
        chart_header_text = chart_header_text .. " \xe2\x80\xba"
        local chart_header = buildSectionHeader(fonts.section, chart_header_text, layout.full_width)
        local tappable_chart_header = InputContainer:new{
            dimen = chart_header:getSize(),
            chart_header,
        }
        tappable_chart_header.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return tappable_chart_header.dimen end } },
        }
        function tappable_chart_header:onTap()
            popup_self:cycleInsightsMode()
            return true
        end
        addSectionWithRow(sections, tappable_chart_header, chart, layout, { add_divider = true, no_bottom_line = false })
    end

    -- ÖSSZES OLVASÁS szekció (évszűrés nélkül) — az éves/havi bontás alatt
    do
        local all_hours = all_time_stats and all_time_stats.hours or 0
        local all_pages = all_time_stats and all_time_stats.pages or 0

        local all_time_val  = formatNumber(all_hours, 0)
        local all_time_unit = N_("hour read", "hours read", all_hours)
        local all_pages_val  = formatCount(all_pages)
        local all_pages_unit = N_("page read", "pages read", all_pages)

        local left_line  = buildValueLine(fonts.value, fonts.label, layout.col_width, all_time_val,  all_time_unit)
        local right_line = buildValueLine(fonts.value, fonts.label, layout.col_width, all_pages_val, all_pages_unit)

        local left_cell = InputContainer:new{
            dimen = Geom:new{ w = layout.col_width, h = left_line:getSize().h },
            left_line,
        }
        left_cell.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return left_cell.dimen end } },
        }
        function left_cell:onTap()
            popup_self:showAllBooks()
            return true
        end

        local right_cell = InputContainer:new{
            dimen = Geom:new{ w = layout.col_width, h = right_line:getSize().h },
            right_line,
        }
        right_cell.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return right_cell.dimen end } },
        }
        function right_cell:onTap()
            popup_self:showAllBooks()
            return true
        end

        local all_time_row = buildTwoColRow(left_cell, right_cell, layout)

        -- Header: book count from all_time_stats
        local all_book_count = all_time_stats and all_time_stats.book_count or 0
        local header_text = _("TOTAL READ")

        addSectionWithRow(sections,
            buildSectionHeader(fonts.section, header_text, layout.full_width),
            all_time_row, layout, { no_bottom_line = true })
    end

    return sections
end

Dispatcher:registerAction("reading_insights_popup", {
    category = "none",
    event    = "ShowReadingInsightsPopup",
    title    = _("Reading statistics: reading insights"),
    general  = true,
})

ReadingInsightsPopup = InputContainer:extend{
    modal         = true,
    ui            = nil,
    width         = nil,
    height        = nil,
    selected_year = nil,
    mode          = nil,
}

function ReadingInsightsPopup:calculateStreaks()
    local today = todayDateStr()
    if ENABLE_CACHE and _cache.streaks and _cache.streaks_date == today then
        return _cache.streaks
    end

    local streaks = {
        current_days  = 0,
        best_days     = 0,
        current_weeks = 0,
        best_weeks    = 0,
    }

    local result = withStatsDb(streaks, function(conn)
        local dates = {}
        local sql = "SELECT DISTINCT date(start_time, 'unixepoch', 'localtime') as d FROM page_stat ORDER BY d DESC"
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do table.insert(dates, row[1]) end
        end)

        local today_str   = os.date("%Y-%m-%d")
        local yesterday   = os.date("%Y-%m-%d", os.time() - 86400)

        local function isCurrentDayStart(first_date)
            return first_date == today_str or first_date == yesterday
        end

        local function isConsecutiveDay(prev_date, curr_date)
            local year, month, day = parseDateYMD(prev_date)
            if not year then return false end
            local prev_time   = os.time({ year = year, month = month, day = day })
            local expected_prev = os.date("%Y-%m-%d", prev_time - 86400)
            return curr_date == expected_prev
        end

        streaks.current_days, streaks.best_days =
            computeStreaks(dates, isConsecutiveDay, isCurrentDayStart)

        local weeks    = {}
        local sql_weeks = "SELECT DISTINCT strftime('%Y-%W', start_time, 'unixepoch', 'localtime') as w FROM page_stat ORDER BY w DESC"
        withStatement(conn, sql_weeks, function(stmt_weeks)
            for row in stmt_weeks:rows() do table.insert(weeks, row[1]) end
        end)

        local current_week = os.date("%Y-%W")
        local last_week    = os.date("%Y-%W", os.time() - 7 * 86400)

        local function isCurrentWeekStart(first_week)
            return first_week == current_week or first_week == last_week
        end

        local function isConsecutiveWeek(prev_week, curr_week)
            local prev_year, prev_wk = parseWeekYear(prev_week)
            local curr_year, curr_wk = parseWeekYear(curr_week)
            if not prev_year or not curr_year then return false end
            if prev_year == curr_year and prev_wk == curr_wk + 1 then return true end
            if prev_year == curr_year + 1 and prev_wk == 0 and curr_wk >= 52 then return true end
            return false
        end

        streaks.current_weeks, streaks.best_weeks =
            computeStreaks(weeks, isConsecutiveWeek, isCurrentWeekStart)

        return streaks
    end)

    if ENABLE_CACHE then
        _cache.streaks      = result
        _cache.streaks_date = today
        _stale_cache.streaks = result
    end
    return result
end

function ReadingInsightsPopup:getMonthlyReadingDays(year)
    local key = "days:" .. year .. ":" .. todayDateStr()
    if ENABLE_CACHE and _monthly_cache[key] then return _monthly_cache[key] end

    local months = {}
    local result = withStatsDb(months, function(conn)
        local year_str = tostring(year)
        local sql = string.format([[
            SELECT strftime('%%Y-%%m', start_time, 'unixepoch', 'localtime') AS month,
                   COUNT(DISTINCT date(start_time, 'unixepoch', 'localtime')) AS days_read
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
            GROUP BY month
            ORDER BY month ASC
        ]], year_str)

        local results = {}
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do results[row[1]] = row[2] end
        end)

        for month_num = 1, 12 do
            local year_month = string.format("%04d-%02d", year, month_num)
            local days = tonumber(results[year_month]) or 0
            table.insert(months, {
                month      = year_month,
                days       = days,
                label      = MONTH_NAMES_SHORT[month_num],
                label_full = MONTH_NAMES_FULL[month_num],
            })
        end
        return months
    end)

    if ENABLE_CACHE then
        _monthly_cache[key] = result
        _stale_monthly[key] = result
    end
    return result
end

function ReadingInsightsPopup:getMonthlyReadingHours(year)
    local key = "hours:" .. year .. ":" .. todayDateStr()
    if ENABLE_CACHE and _monthly_cache[key] then return _monthly_cache[key] end

    local months = {}
    local result = withStatsDb(months, function(conn)
        local year_str = tostring(year)
        local sql = string.format([[
            SELECT dates AS month,
                   SUM(sum_duration) / 3600.0 AS hours_read
            FROM (
                SELECT strftime('%%Y-%%m', start_time, 'unixepoch', 'localtime') AS dates,
                       sum(duration) AS sum_duration
                FROM page_stat
                WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
                GROUP BY id_book, page, dates
            )
            GROUP BY dates
            ORDER BY dates ASC
        ]], year_str)

        local results = {}
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do results[row[1]] = row[2] end
        end)

        for month_num = 1, 12 do
            local year_month = string.format("%04d-%02d", year, month_num)
            local hours = tonumber(results[year_month]) or 0
            if hours >= 1 then
                hours = math.floor(hours)
            elseif hours > 0 then
                hours = (math.floor(hours * 10)) / 10
            end
            table.insert(months, {
                month      = year_month,
                hours      = hours,
                label      = MONTH_NAMES_SHORT[month_num],
                label_full = MONTH_NAMES_FULL[month_num],
            })
        end
        return months
    end)

    if ENABLE_CACHE then
        _monthly_cache[key] = result
        _stale_monthly[key] = result
    end
    return result
end


function ReadingInsightsPopup:getYearlyStats(year)
    local key = year .. ":v3:" .. todayDateStr()
    if ENABLE_CACHE and _yearly_cache[key] then return _yearly_cache[key] end

    local stats  = { days = 0, pages = 0, duration = 0, books_started = 0 }
    local result = withStatsDb(stats, function(conn)
        local year_str = tostring(year)

        local sql_days = string.format([[
            SELECT COUNT(DISTINCT date(start_time, 'unixepoch', 'localtime'))
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
        ]], year_str)
        withStatement(conn, sql_days, function(stmt_days)
            for row in stmt_days:rows() do stats.days = tonumber(row[1]) or 0 end
        end)

        local sql_pages = string.format([[
            SELECT count(*)
            FROM (
                SELECT 1
                FROM page_stat
                WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
                GROUP BY id_book, page
            )
        ]], year_str)
        withStatement(conn, sql_pages, function(stmt_pages)
            for row in stmt_pages:rows() do stats.pages = tonumber(row[1]) or 0 end
        end)

        local sql_duration = string.format([[
            SELECT SUM(sum_duration)
            FROM (
                SELECT SUM(duration) AS sum_duration
                FROM page_stat
                WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
                GROUP BY id_book, page, date(start_time, 'unixepoch', 'localtime')
            )
        ]], year_str)
        withStatement(conn, sql_duration, function(stmt_duration)
            for row in stmt_duration:rows() do
                stats.duration = tonumber(row[1]) or 0
            end
        end)

        local sql_started = string.format([[
            SELECT COUNT(DISTINCT id_book)
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
        ]], year_str)
        withStatement(conn, sql_started, function(stmt_started)
            for row in stmt_started:rows() do stats.books_started = tonumber(row[1]) or 0 end
        end)

        return stats
    end)

    if ENABLE_CACHE then
        _yearly_cache[key] = result
        _stale_yearly[key] = result
    end
    return result
end

-- Single DB connection: getTodayStats and getYearRange merged into one query.
-- Both values are fetched in a single withStatsDb call to avoid opening two
-- separate connections.
function ReadingInsightsPopup:getTodayAndYearRange()
    local minute       = currentMinute()
    local today        = todayDateStr()
    local today_cached = ENABLE_CACHE and _cache.today and _cache.today_minute == minute
    local range_cached = ENABLE_CACHE and _cache.year_range and _cache.year_range_date == today

    if today_cached and range_cached then
        return _cache.today, _cache.year_range
    end

    local current_year = tonumber(os.date("%Y"))
    local stats = { seconds = 0, pages = 0 }
    local range = range_cached
        and _cache.year_range
        or  { min_year = current_year, max_year = current_year }

    withStatsDb(nil, function(conn)
        if not today_cached then
            local now_ts  = os.time()
            local now_t   = os.date("*t")
            local start_today_time = now_ts - (now_t.hour * 3600 + now_t.min * 60 + now_t.sec)
            local sql = string.format([[
                SELECT count(*), sum(sum_duration)
                FROM (
                    SELECT sum(duration) AS sum_duration
                    FROM page_stat
                    WHERE start_time >= %d
                      AND duration > 2
                    GROUP BY id_book, page
                );
            ]], start_today_time)
            withStatement(conn, sql, function(stmt)
                for row in stmt:rows() do
                    stats.pages   = tonumber(row[1]) or 0
                    stats.seconds = tonumber(row[2]) or 0
                end
            end)
            if ENABLE_CACHE then
                _cache.today        = stats
                _cache.today_minute = minute
                _stale_cache.today  = stats
            end
        end

        if not range_cached then
            local sql_range = [[
                SELECT MIN(strftime('%Y', start_time, 'unixepoch', 'localtime')) AS min_year,
                       MAX(strftime('%Y', start_time, 'unixepoch', 'localtime')) AS max_year
                FROM page_stat
            ]]
            withStatement(conn, sql_range, function(stmt)
                for row in stmt:rows() do
                    if row[1] then range.min_year = tonumber(row[1]) or current_year end
                    if row[2] then range.max_year = tonumber(row[2]) or current_year end
                end
            end)
            if ENABLE_CACHE then
                _cache.year_range      = range
                _cache.year_range_date = today
                _stale_cache.year_range = range
            end
        end
    end)

    return
        (today_cached and _cache.today or stats),
        (range_cached and _cache.year_range or range)
end

-- Backward-compatible standalone wrappers — delegate to the merged function above.
function ReadingInsightsPopup:getTodayStats()
    local today, _ = self:getTodayAndYearRange()
    return today
end

function ReadingInsightsPopup:getYearRange()
    local _, range = self:getTodayAndYearRange()
    return range
end

function ReadingInsightsPopup:getAllTimeStats()
    local today = todayDateStr()
    if ENABLE_CACHE and _cache.all_time and _cache.all_time_date == today then return _cache.all_time end

    local year_range = self:getYearRange()
    local total_hours = 0
    local total_pages = 0

    for year = year_range.min_year, year_range.max_year do
        local ys = self:getYearlyStats(year)
        -- Use the same rounding as the yearly display (formatHoursRead)
        local rounded_minutes = Math.round(ys.duration / 60)
        local h = math.floor(math.floor(rounded_minutes / 60 * 10) / 10)
        total_hours = total_hours + h
        total_pages = total_pages + (ys.pages or 0)
    end

    local book_count = withStatsDb(0, function(conn)
        local count = 0
        withStatement(conn, "SELECT COUNT(DISTINCT id_book) FROM page_stat", function(stmt)
            for row in stmt:rows() do count = tonumber(row[1]) or 0 end
        end)
        return count
    end)

    local result = { hours = total_hours, pages = total_pages, book_count = book_count }
    if ENABLE_CACHE then
        _cache.all_time      = result
        _cache.all_time_date = today
        _stale_cache.all_time = result
    end
    return result
end

-- Last 7-day averages: total reading time (seconds) / 7 and total pages / 7.
-- The 7-day window runs backwards from midnight today (7 × 86400 seconds).
function ReadingInsightsPopup:getLastWeekStats()
    local today = todayDateStr()
    local minute = currentMinute()
    if ENABLE_CACHE and _cache.last_week and _cache.last_week_minute == minute then
        return _cache.last_week
    end

    local result = { avg_seconds = 0, avg_pages = 0 }

    withStatsDb(nil, function(conn)
        -- 7-day window: today's midnight minus 6 days
        local now_ts  = os.time()
        local now_t   = os.date("*t")
        local today_midnight = now_ts - (now_t.hour * 3600 + now_t.min * 60 + now_t.sec)
        local week_start_ts  = today_midnight - 6 * 86400

        -- Reading time: de-duplicated pages (GROUP BY id_book, page, day)
        local sql_sec = string.format([[
            SELECT SUM(sum_dur)
            FROM (
                SELECT SUM(duration) AS sum_dur
                FROM page_stat
                WHERE start_time >= %d
                  AND duration > 2
                GROUP BY id_book, page, date(start_time, 'unixepoch', 'localtime')
            )
        ]], week_start_ts)
        withStatement(conn, sql_sec, function(stmt)
            for row in stmt:rows() do
                result.avg_seconds = (tonumber(row[1]) or 0) / 7
            end
        end)

        -- Pages: de-duplicated (GROUP BY id_book, page)
        local sql_pages = string.format([[
            SELECT COUNT(*)
            FROM (
                SELECT 1
                FROM page_stat
                WHERE start_time >= %d
                  AND duration > 2
                GROUP BY id_book, page
            )
        ]], week_start_ts)
        withStatement(conn, sql_pages, function(stmt)
            for row in stmt:rows() do
                result.avg_pages = (tonumber(row[1]) or 0) / 7
            end
        end)
    end)

    if ENABLE_CACHE then
        _cache.last_week        = result
        _cache.last_week_minute = minute
        _stale_cache.last_week  = result
    end
    return result
end

local function getBooksForPeriod(period_format, period_value)
    local books = {}
    return withStatsDb(books, function(conn)
        -- Reading time per book for the given period (seconds), de-duplicated (GROUP BY id_book, page).
        -- period_format is an SQLite strftime format string (e.g. '%%Y-%%m'); it is inserted via
        -- string concatenation rather than string.format to avoid conflicting with %% escapes.
        -- Finish date: taken globally from all page_stat rows when the book is >= 97% read.
        -- If no finish date exists (book not finished), falls back to the first read time in the period.
        local sql = [[
            SELECT book.title, book.authors,
                   COUNT(DISTINCT ps_dedup.page) AS pages_read,
                   SUM(ps_dedup.period_sum) AS duration_sec,
                   fin.finish_time,
                   MIN(ps_dedup.first_read) AS first_read_time,
                   day_counts.days_read,
                   book.id AS id_book
            FROM (
                SELECT id_book, page,
                       SUM(duration) AS period_sum,
                       MIN(start_time) AS first_read
                FROM page_stat
                WHERE strftime(']] .. period_format .. [[', start_time, 'unixepoch', 'localtime') = ']] .. period_value .. [['
                GROUP BY id_book, page
            ) ps_dedup
            JOIN book ON ps_dedup.id_book = book.id
            LEFT JOIN (
                SELECT ps2.id_book, MAX(ps2.start_time) AS finish_time
                FROM page_stat ps2
                JOIN book b2 ON ps2.id_book = b2.id
                WHERE b2.pages > 0
                GROUP BY ps2.id_book
                HAVING MAX(ps2.page) >= b2.pages
            ) fin ON ps_dedup.id_book = fin.id_book
            LEFT JOIN (
                SELECT id_book,
                       COUNT(DISTINCT date(start_time, 'unixepoch', 'localtime')) AS days_read
                FROM page_stat
                WHERE strftime(']] .. period_format .. [[', start_time, 'unixepoch', 'localtime') = ']] .. period_value .. [['
                GROUP BY id_book
            ) day_counts ON ps_dedup.id_book = day_counts.id_book
            GROUP BY ps_dedup.id_book
            ORDER BY COALESCE(fin.finish_time, MIN(ps_dedup.first_read)) DESC
        ]]

        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                table.insert(books, {
                    title     = row[1] or _("Unknown"),
                    authors   = "",
                    pages     = tonumber(row[3]) or 0,
                    duration  = tonumber(row[4]) or 0,
                    days_read = tonumber(row[7]) or 0,
                    id_book   = tonumber(row[8]),
                })
            end
        end)
        return books
    end)
end

local function getAllBooks()
    local books = {}
    return withStatsDb(books, function(conn)
        local sql = [[
            SELECT book.title, book.authors,
                   COUNT(DISTINCT ps_dedup.page) AS pages_read,
                   SUM(ps_dedup.period_sum) AS duration_sec,
                   MAX(ps_dedup.last_read) AS last_read_time,
                   book.id AS id_book
            FROM (
                SELECT id_book, page,
                       SUM(duration) AS period_sum,
                       MAX(start_time) AS last_read
                FROM page_stat
                GROUP BY id_book, page
            ) ps_dedup
            JOIN book ON ps_dedup.id_book = book.id
            GROUP BY ps_dedup.id_book
            ORDER BY last_read_time DESC
        ]]
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                table.insert(books, {
                    title    = row[1] or _("Unknown"),
                    authors  = "",
                    pages    = tonumber(row[3]) or 0,
                    duration = tonumber(row[4]) or 0,
                    id_book  = tonumber(row[6]),
                })
            end
        end)
        return books
    end)
end

function ReadingInsightsPopup:getBooksForMonth(year_month)
    return getBooksForPeriod("%Y-%m", year_month)
end

local function showBookList(title, books, on_close, stats_plugin)
    local KeyValuePage = require("ui/widget/keyvaluepage")

    if #books == 0 then
        UIManager:show(InfoMessage:new{ text = _("No books read") })
        return
    end

    local kv_pairs = {}
    for _, book in ipairs(books) do
        local display_text = book.title
        if book.authors and book.authors ~= "" then
            display_text = display_text .. "\n" .. book.authors
        end
        -- Egységes formátum: HH:MM:SS (X oldal)
        local time_str
        if book.duration and book.duration > 0 then
            time_str = formatHHMMSS(book.duration)
        else
            time_str = "00:00:00"
        end
        local pages_str = "(" .. formatCount(book.pages) .. " " .. N_("page", "pages", book.pages) .. ")"
        local time_text = time_str .. " " .. pages_str
        local book_id = book.id_book
        local book_title = book.title
        local cb = nil
        if book_id and stats_plugin then
            cb = function()
                local kv2
                kv2 = KeyValuePage:new{
                    title           = book_title,
                    kv_pairs        = stats_plugin:getBookStat(book_id),
                    value_align     = "right",
                    single_page     = true,
                    callback_return = function()
                        UIManager:close(kv2)
                    end,
                    close_callback  = function() kv2 = nil end,
                }
                UIManager:show(kv2)
            end
        end
        table.insert(kv_pairs, {
            display_text,
            time_text,
            callback = cb,
        })
    end

    local kv
    kv = KeyValuePage:new{
        title          = title,
        kv_pairs       = kv_pairs,
        value_align    = "right",
        close_callback = function()
            UIManager:close(kv)
            UIManager:scheduleIn(0, function()
                if on_close then on_close() end
            end)
        end,
    }
    UIManager:show(kv)
end

local function showBooksForPeriod(popup_self, books, empty_text, title)
    if #books == 0 then
        UIManager:show(InfoMessage:new{ text = empty_text })
        return
    end

    local saved_year     = popup_self.selected_year
    local saved_mode     = popup_self.mode
    local saved_ui       = popup_self.ui
    -- Preserve cached data so the new instance skips DB queries.
    -- _today is excluded: the global _cache.today (per-minute) handles it.
    local saved_streaks  = popup_self._streaks
    local saved_yr       = popup_self._year_range
    local saved_yearly   = popup_self._yearly
    local saved_monthly  = popup_self._monthly
    local saved_all_time = popup_self._all_time

    popup_self._closed = true
    UIManager:close(popup_self)

    local stats_plugin = saved_ui and saved_ui.statistics or nil
    showBookList(title, books, function()
        local p = ReadingInsightsPopup:new{
            ui            = saved_ui,
            selected_year = saved_year,
            mode          = saved_mode,
            _streaks      = saved_streaks,
            _year_range   = saved_yr,
            _yearly       = saved_yearly,
            _monthly      = saved_monthly,
            _all_time     = saved_all_time,
        }
        UIManager:show(p)
    end, stats_plugin)
end

function ReadingInsightsPopup:showBooksForMonth(year_month, month_label_full)
    local books
    local title
    books = self:getBooksForMonth(year_month)
    title = T(N_("%1 - book read (%2)", "%1 - books read (%2)", #books), month_label_full, #books)
    showBooksForPeriod(
        self, books,
        T(_("No books read in %1"), month_label_full),
        title)
end

function ReadingInsightsPopup:getBooksForYear(year)
    return getBooksForPeriod("%Y", tostring(year))
end


function ReadingInsightsPopup:showAllBooks()
    local books = getAllBooks()
    showBooksForPeriod(
        self, books,
        _("No books read"),
        _("ALL BOOKS READ") .. " (" .. formatCount(#books) .. ")")
end

function ReadingInsightsPopup:showBooksForYear(year)
    local books = self:getBooksForYear(year)
    showBooksForPeriod(
        self, books,
        _("No books read in ") .. year,
        T(N_("%1 - book read (%2)", "%1 - books read (%2)", #books), year, #books))
end

-- Explicit popup_frame.dimen assignment so setDirty only repaints the popup area.
function ReadingInsightsPopup:_buildUI()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local fonts    = buildSerifFonts()
    local layout   = buildLayout(screen_w, Size.padding.large, Screen:scaleBySize(20))

    local sections = buildInsightsSections(
        self,
        self._streaks    or { current_days=0, best_days=0, current_weeks=0, best_weeks=0 },
        self._yearly     or { days=0, pages=0, duration=0 },
        self._year_range or { min_year=self.selected_year, max_year=self.selected_year },
        self._monthly    or {},
        self._today      or { seconds=0, pages=0 },
        self._all_time   or { hours=0, pages=0 },
        self._last_week  or { avg_seconds=0, avg_pages=0 },
        fonts, layout)

    -- Native KOReader TitleBar with built-in close button (calendarview.lua style)
    local title_bar = TitleBar:new{
        fullscreen     = true,
        width          = screen_w,
        align          = "left",
        title          = _("Reading insights"),
        close_callback = function() UIManager:close(self) end,
        show_parent    = self,
        top_v_padding    = Size.padding.default,
        bottom_v_padding = Size.padding.default,
    }

    -- Scroll content: TitleBar + sections + bottom padding
    local content = VerticalGroup:new{
        align = "left",
        title_bar,
        padded(layout.padding_h, LineWidget:new{
            dimen      = Geom:new{ w = layout.content_width, h = Size.line.thick },
            background = Blitbuffer.COLOR_GRAY,
        }),
        sections,
        VerticalSpan:new{ height = title_bar:getSize().h },
    }

    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")

    self.scroll_container = ScrollableContainer:new{
        dimen               = Geom:new{ w = screen_w, h = screen_h },
        show_parent         = self,
        scroll_bar_position = "right",
        content,
    }

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius     = 0,
        padding    = 0,
        width      = screen_w,
        VerticalGroup:new{
            align = "left",
            self.scroll_container,
        },
    }

    self.popup_frame.dimen = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h }

    self[1] = VerticalGroup:new{ self.popup_frame }
end

function ReadingInsightsPopup:_loadAndRebuild()
    if not self._streaks then self._streaks = self:calculateStreaks() end
    self._today, self._year_range = self:getTodayAndYearRange()
    if not self._yearly   then self._yearly   = self:getYearlyStats(self.selected_year) end
    if not self._all_time then self._all_time  = self:getAllTimeStats() end
    if not self._last_week then self._last_week = self:getLastWeekStats() end
    if not self._monthly then
        if self.mode == INSIGHTS_MODE_HOURS then
            self._monthly = self:getMonthlyReadingHours(self.selected_year)
        else
            self._monthly = self:getMonthlyReadingDays(self.selected_year)
        end
    end

    self:_buildUI()
    UIManager:setDirty(self, function()
        return "ui", self.popup_frame.dimen
    end)
end

-- _buildUI must not run twice: init() performs only the minimum setup, then a
-- single scheduleIn(0) call triggers the full data load and UI build.
--
-- Stale-while-revalidate: if previous data is available in the stale cache
-- (expired or still valid), it is shown immediately while fresh values are
-- loaded in the background. The popup always opens with data, never blank.
function ReadingInsightsPopup:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    -- 1. Load fresh cache entries (if still valid)
    if ENABLE_CACHE then
        self._streaks    = self._streaks    or _cache.streaks
        local minute = currentMinute()
        self._today = self._today or (
            _cache.today and _cache.today_minute == minute and _cache.today or nil
        )
        self._year_range = self._year_range or _cache.year_range
        self._all_time   = self._all_time   or _cache.all_time
        local year_key = (self.selected_year or tonumber(os.date("%Y"))) .. ":v3:" .. todayDateStr()
        self._yearly  = self._yearly  or _yearly_cache[year_key]
        local mode = normalizeInsightsMode(self.mode or readInsightsMode())
        local month_key_prefix = (mode == INSIGHTS_MODE_HOURS and "hours:" or
                                  "days:")
        local month_key = month_key_prefix .. (self.selected_year or tonumber(os.date("%Y"))) .. ":" .. todayDateStr()
        self._monthly = self._monthly or _monthly_cache[month_key]
    end

    -- 2. Fall back to stale (expired) cache for any data still missing.
    --    This enables immediate display after a restart or day rollover.
    if ENABLE_CACHE then
        local year_key_any   = (self.selected_year or tonumber(os.date("%Y"))) .. ":v3:"
        local mode_fb = normalizeInsightsMode(self.mode or readInsightsMode())
        local month_key_prefix_fb = (mode_fb == INSIGHTS_MODE_HOURS and "hours:" or
                                     "days:")
        local month_key_fb = month_key_prefix_fb .. (self.selected_year or tonumber(os.date("%Y"))) .. ":"

        -- streaks: any age is acceptable
        if not self._streaks then
            self._streaks = _stale_cache.streaks
        end
        -- today: minute-sensitive, but stale is better than nothing
        if not self._today then
            self._today = _stale_cache.today
        end
        -- year_range: day-sensitive, stale is acceptable
        if not self._year_range then
            self._year_range = _stale_cache.year_range
        end
        -- all_time: day-sensitive, stale is acceptable
        if not self._all_time then
            self._all_time = _stale_cache.all_time
        end
        -- last_week: minute-sensitive, stale is acceptable
        if not self._last_week then
            self._last_week = _stale_cache.last_week
        end
        -- yearly: look for any stale entry for the current year
        if not self._yearly then
            for k, v in pairs(_stale_yearly) do
                if k:sub(1, #year_key_any) == year_key_any then
                    self._yearly = v
                    break
                end
            end
        end
        -- monthly: look for any stale entry for the current year + mode
        if not self._monthly then
            for k, v in pairs(_stale_monthly) do
                if k:sub(1, #month_key_fb) == month_key_fb then
                    self._monthly = v
                    break
                end
            end
        end
    end

    self.mode = normalizeInsightsMode(self.mode or readInsightsMode())

    -- year_range is fetched inside _loadAndRebuild via getTodayAndYearRange,
    -- but selected_year needs an initial value — default to the current year.
    if not self.selected_year then
        self.selected_year = tonumber(os.date("%Y"))
    end

    self.dimen = Geom:new{ w = screen_w, h = screen_h }

    if Device:isTouchDevice() then
        -- TapClose intentionally omitted: only the top-right X button closes the popup.
        self.ges_events.Swipe    = { GestureRange:new{ ges = "swipe", range = self.dimen } }
        self.ges_events.Hold     = { GestureRange:new{ ges = "hold",  range = self.dimen } }
    end
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end

    -- Always build UI first so popup_frame exists before UIManager repaints.
    -- Stale or fresh data is shown immediately; _loadAndRebuild always runs
    -- in the background to refresh with up-to-date values.
    self:_buildUI()
    if self._streaks or self._yearly or self._monthly then
        -- Something to show (stale or fresh): draw immediately,
        -- then refresh from DB in the background.
        UIManager:scheduleIn(0, function()
            if self._closed then return end
            self:_loadAndRebuild()
        end)
    else
        UIManager:scheduleIn(0, function()
            if self._closed then return end
            self:_loadAndRebuild()
        end)
    end
end

function ReadingInsightsPopup:onSwipe(arg, ges_ev)
    if not ges_ev then return false end
    local dir = ges_ev.direction
    if dir == "west" or dir == "left"  then return self:onGoToNextYear() end
    if dir == "east" or dir == "right" then return self:onGoToPrevYear() end
    if dir == "south" or dir == "down" then UIManager:close(self) return true end
    return false
end

-- Fallback hold handler on the popup level (catches holds outside the TODAY header,
-- e.g. when TODAY section is hidden because there is no reading today yet).
function ReadingInsightsPopup:onHold()
    local msg = InfoMessage:new{ text = _("Reloading data...") }
    UIManager:show(msg)
    UIManager:scheduleIn(0.5, function()
        UIManager:close(msg)
        clearAllCache()
        self._streaks  = nil
        self._today    = nil
        self._yearly   = nil
        self._monthly  = nil
        self._all_time = nil
        self._last_week = nil
        self:_loadAndRebuild()
    end)
    return true
end

function ReadingInsightsPopup:toggleInsightsMode()
    local new_mode = self.mode == INSIGHTS_MODE_HOURS and INSIGHTS_MODE_DAYS or INSIGHTS_MODE_HOURS
    saveInsightsMode(new_mode)
    self.mode     = new_mode
    self._monthly = nil
    self:_loadAndRebuild()
    return true
end

-- Tap on monthly header: cycle hours → days → hours
function ReadingInsightsPopup:cycleInsightsMode()
    local new_mode
    if self.mode == INSIGHTS_MODE_HOURS then
        new_mode = INSIGHTS_MODE_DAYS
    else
        new_mode = INSIGHTS_MODE_HOURS
    end

    saveInsightsMode(new_mode)

    self.mode = new_mode
    self._monthly = nil
    self:_loadAndRebuild()
    return true
end

function ReadingInsightsPopup:onGoToPrevYear()
    local yr = self._year_range or self.year_range
    if yr and self.selected_year > yr.min_year then
        self.selected_year = self.selected_year - 1
        self._monthly      = nil
        self._yearly       = nil
        self:_loadAndRebuild()
    end
    return true
end

function ReadingInsightsPopup:onAnyKeyPressed(_, key)
    if key and key:match({ { "RPgBack", "LPgBack", "Left"  } }) then return self:onGoToPrevYear() end
    if key and key:match({ { "RPgFwd",  "LPgFwd",  "Right" } }) then return self:onGoToNextYear() end
    if key and key:match({ { "Press" } }) then return self:toggleInsightsMode() end
    UIManager:close(self)
    return true
end

function ReadingInsightsPopup:onGoToNextYear()
    local yr = self._year_range or self.year_range
    if yr and self.selected_year < yr.max_year then
        self.selected_year = self.selected_year + 1
        self._monthly      = nil
        self._yearly       = nil
        self:_loadAndRebuild()
    end
    return true
end

function ReadingInsightsPopup:onShow()
    if FULL_SCREEN_REFRESH_ON_OPEN_CLOSE then
        UIManager:setDirty(self, function()
            return "full", self.popup_frame.dimen
        end)
    else
        UIManager:setDirty(self, function()
            return "ui", self.popup_frame.dimen
        end)
    end
    return true
end

function ReadingInsightsPopup:onTapClose()
    UIManager:close(self)
    return true
end

function ReadingInsightsPopup:onCloseWidget()
    self._closed = true
    if self.scroll_container then
        self.scroll_container:free()
    end
    if FULL_SCREEN_REFRESH_ON_OPEN_CLOSE then
        UIManager:setDirty(nil, "full")
    else
        UIManager:setDirty(nil, "ui")
    end
end

function ReaderUI.onShowReadingInsightsPopup(this)
    local popup = ReadingInsightsPopup:new{ ui = this }
    UIManager:show(popup)
    return true
end

function FileManager:onShowReadingInsightsPopup()
    local popup = ReadingInsightsPopup:new{ ui = self }
    UIManager:show(popup)
    return true
end