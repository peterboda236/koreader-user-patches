-- Add Night mode Toggle to the bottom of the frontlight widget.
local FrontLightWidget = require("ui/widget/frontlightwidget")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local _ = require("gettext")

local original_layout = FrontLightWidget.layout

FrontLightWidget.layout = function(self)
    original_layout(self)

    self.nm_button = Button:new{
        text = _("Toggle"),
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

    self.layout[#self.layout + 1] = { self.nm_button }

    local function centered(widget)
        return CenterContainer:new{
            dimen = Geom:new{ w = self.inner_width, h = widget:getSize().h },
            widget,
        }
    end

    table.insert(self.frame[1], VerticalGroup:new{
        VerticalSpan:new{ width = Size.span.vertical_large * 4 },
        centered(TextWidget:new{
            text = _("Night mode"),
            face = self.medium_font_face,
            bold = true,
            max_width = self.inner_width,
        }),
        VerticalSpan:new{ width = self.span },
        centered(self.nm_button),
        VerticalSpan:new{ width = self.span * 2 },
    })
end
