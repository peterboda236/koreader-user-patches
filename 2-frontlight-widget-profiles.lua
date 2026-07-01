--[[
FrontLight Widget — Night Mode & Light Profiles
Version 1.0

Extends KOReader's built-in Frontlight dialog (without modifying the base
widget file) with:

  - A Night Mode toggle button.
  - 5 savable light profiles, laid out as:
      Row 1: Night Mode · Profile 1 · Profile 2
      Row 2: Profile 3  · Profile 4 · Profile 5

Usage:
  - Tap a profile button to apply its saved brightness, warmth (on
    natural-light devices), and night-mode state.
  - Long-press a profile button to rename it and save the current
    frontlight settings into that slot.

Profiles are stored via G_reader_settings as "frontlight_profile_<n>"
(settings table) and "frontlight_profile_<n>_name" (display name).
--]]

local FrontLightWidget = require("ui/widget/frontlightwidget")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen

local user_lang = G_reader_settings:readSetting("language") or "en"

local T = {
    en = {
        night_mode         = "Night mode",
        toggle             = "Toggle",
        set                = "Set",
        profile            = "Profile",
        confirm_save_title = "Save current frontlight settings?",
        name_prompt        = "What name would you like to save the profile as?",
        profile_name_hint  = "Profile name",
        cancel             = "Cancel",
        ok                 = "OK",
        no_profile         = "No profile saved for this button.",
    },
    hu = {
        night_mode         = "Éjszakai mód",
        toggle             = "Váltás",
        set                = "Beállít",
        profile            = "Profil",
        confirm_save_title = "Elmentem az aktuális Kijelzővilágítás beállítást?",
        name_prompt        = "Milyen néven szeretnéd a profilt elmenteni?",
        profile_name_hint  = "Profil neve",
        cancel             = "Mégse",
        ok                 = "OK",
        no_profile         = "Nincs elmentett profil ehhez a gombhoz.",
    },
}
local L = T[user_lang] or T.en

local PROFILE_COUNT = 5

local original_layout = FrontLightWidget.layout
FrontLightWidget.layout = function(self)
    original_layout(self)

    -- Always use self.inner_width here, never self.frame[1]:getSize()
    -- (unstable during paintTo, can crash).
    local function centered(widget, w)
        return CenterContainer:new{
            dimen = Geom:new{ w = w or self.inner_width, h = widget:getSize().h },
            widget,
        }
    end

    -- self.frame[1] is an align="left" VerticalGroup, but our blocks are
    -- only inner_width wide, so they'd hug the left edge. Wrap them in a
    -- full self.width CenterContainer to match the original layout.
    local function centered_block(group)
        return CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = group:getSize().h },
            group,
        }
    end

    -- Builds a label row + button row for N same-width columns, spaced to
    -- match the base widget's button padding (outer columns flush to
    -- inner_width edges).
    local function build_row(entries)
        local n = #entries
        local spacer_width = math.floor((self.inner_width - n * self.button_width) / (n - 1))
        local labels_row = HorizontalGroup:new{ align = "center" }
        local buttons_row = HorizontalGroup:new{ align = "center" }
        for idx, entry in ipairs(entries) do
            table.insert(labels_row, centered(entry.label, self.button_width))
            table.insert(buttons_row, entry.button)
            if idx < n then
                table.insert(labels_row, HorizontalSpan:new{ width = spacer_width })
                table.insert(buttons_row, HorizontalSpan:new{ width = spacer_width })
            end
        end
        return VerticalGroup:new{
            align = "center",
            labels_row,
            VerticalSpan:new{ width = self.span },
            buttons_row,
        }
    end

    -- Night mode toggle
    self.nm_button = Button:new{
        text = L.toggle,
        width = self.button_width,
        show_parent = self,
        callback = function()
            G_reader_settings:toggle("night_mode")
            local new_state = G_reader_settings:isTrue("night_mode")
            Screen:toggleNightMode()
            UIManager:setDirty(nil, "full")
            UIManager:broadcastEvent(Event:new("SetNightMode", new_state))
            self:update()
        end,
    }
    local nm_label = TextWidget:new{
        text = L.night_mode,
        face = self.medium_font_face,
        bold = true,
        max_width = self.button_width,
    }

    -- 5 profile buttons
    self.profile_labels = {}
    self.profile_buttons = {}

    for i = 1, PROFILE_COUNT do
        local saved_name = G_reader_settings:readSetting("frontlight_profile_" .. i .. "_name")
            or (L.profile .. " " .. i)

        self.profile_labels[i] = TextWidget:new{
            text = saved_name,
            face = self.medium_font_face,
            bold = true,
            max_width = self.button_width,
        }

        self.profile_buttons[i] = Button:new{
            text = L.set,
            width = self.button_width,
            show_parent = self,
            callback = function()
                self:applyLightProfile(i)
            end,
            hold_callback = function()
                self:saveLightProfileDialog(i)
            end,
        }
    end

    -- Row 1: night mode + profile 1 + profile 2
    local row1 = build_row{
        { label = nm_label, button = self.nm_button },
        { label = self.profile_labels[1], button = self.profile_buttons[1] },
        { label = self.profile_labels[2], button = self.profile_buttons[2] },
    }
    self.layout[#self.layout + 1] = { self.nm_button, self.profile_buttons[1], self.profile_buttons[2] }

    -- Row 2: profile 3 + profile 4 + profile 5
    local row2 = build_row{
        { label = self.profile_labels[3], button = self.profile_buttons[3] },
        { label = self.profile_labels[4], button = self.profile_buttons[4] },
        { label = self.profile_labels[5], button = self.profile_buttons[5] },
    }
    self.layout[#self.layout + 1] = { self.profile_buttons[3], self.profile_buttons[4], self.profile_buttons[5] }

    table.insert(self.frame[1], centered_block(VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Size.span.vertical_large * 4 },
        row1,
        VerticalSpan:new{ width = self.span * 2 },
        row2,
        VerticalSpan:new{ width = self.span * 2 },
    }))
end

-- Save dialog: prompts for a profile name, OK/Cancel
function FrontLightWidget:saveLightProfileDialog(index)
    local current_name = self.profile_labels[index].text
    local dialog
    dialog = InputDialog:new{
        title = L.confirm_save_title,
        description = L.name_prompt,
        input = current_name,
        input_hint = L.profile_name_hint,
        buttons = {
            {
                {
                    text = L.cancel,
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = L.ok,
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        if name == "" then
                            name = L.profile .. " " .. index
                        end
                        self:saveLightProfile(index, name)
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    -- No auto onShowKeyboard(): keyboard only appears on tapping the field,
    -- avoiding a stray keypress from the hold-release touch.
    UIManager:show(dialog)
end

-- Save current brightness / warmth / night mode into a profile
function FrontLightWidget:saveLightProfile(index, name)
    local profile = {
        name = name,
        brightness = self.powerd:frontlightIntensity(),
        night_mode = G_reader_settings:isTrue("night_mode"),
    }
    if Device:hasNaturalLight() then
        profile.warmth = self.powerd:frontlightWarmth()
    end

    G_reader_settings:saveSetting("frontlight_profile_" .. index, profile)
    G_reader_settings:saveSetting("frontlight_profile_" .. index .. "_name", name)

    self.profile_labels[index]:setText(name)
    UIManager:setDirty(self, "ui")
end

-- Apply a saved profile on tap
function FrontLightWidget:applyLightProfile(index)
    local profile = G_reader_settings:readSetting("frontlight_profile_" .. index)
    if not profile then
        UIManager:show(InfoMessage:new{ text = L.no_profile })
        return
    end

    self.powerd:setIntensity(profile.brightness)

    if profile.warmth and Device:hasNaturalLight() then
        self.powerd:setWarmth(profile.warmth)
    end

    local current_nm = G_reader_settings:isTrue("night_mode")
    if profile.night_mode ~= current_nm then
        G_reader_settings:saveSetting("night_mode", profile.night_mode)
        Screen:toggleNightMode()
        UIManager:broadcastEvent(Event:new("SetNightMode", profile.night_mode))
    end

    -- Reopen as a fresh instance instead of free()+init() on the same self:
    -- our patched "layout" method would collide with the instance-level
    -- self.layout field set on init.
    UIManager:close(self)
    UIManager:show(FrontLightWidget:new{})
    UIManager:setDirty(nil, "full")
end