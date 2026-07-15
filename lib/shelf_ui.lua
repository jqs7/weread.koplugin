--[[--
WeRead bookshelf list with left-aligned cover thumbnails.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local CoverCache = require("lib.cover_cache")
local I18n = require("lib.i18n")

local Screen = Device.screen
local getMenuText = Menu.getMenuText

local function _(text)
    return I18n.tr(text)
end

local COVER_ROW_HEIGHT = Screen:scaleBySize(72)

local function bookIdOf(book)
    if not book then
        return nil
    end
    return book.book_id or book.bookId
end

local function coverUrlOf(book)
    if not book then
        return nil
    end
    return book.cover
end

local ShelfMenuItem = InputContainer:extend{
    entry = nil,
    menu = nil,
    dimen = nil,
}

function ShelfMenuItem:init()
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }

    local dimen = self.dimen
    local entry = self.entry
    local pad_v = Size.span.vertical_default
    local pad_h_left = Screen:scaleBySize(10)
    local inner_h = dimen.h - 2 * pad_v

    if not entry.book then
        local mandatory = entry.mandatory_func and entry.mandatory_func() or entry.mandatory
        local mandatory_w = 0
        if mandatory and mandatory ~= "" then
            mandatory_w = TextWidget:new{
                text = mandatory,
                face = Font:getFace("infont", self.infont_size or 16),
                fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
            }:getWidth() + Size.span.horizontal_default
        end
        local text_w = dimen.w - pad_h_left - mandatory_w - Size.span.horizontal_default
        local text_widget = TextBoxWidget:new{
            text = getMenuText(entry),
            face = Font:getFace("smallinfofont", self.font_size or 20),
            width = text_w,
            max_lines = 2,
            fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
            bold = entry.bold,
        }
        local hgroup_items = {
            HorizontalSpan:new{ width = pad_h_left },
            CenterContainer:new{
                dimen = Geom:new{ w = text_w, h = inner_h },
                text_widget,
            },
        }
        if mandatory and mandatory ~= "" then
            hgroup_items[#hgroup_items + 1] = RightContainer:new{
                dimen = Geom:new{ w = mandatory_w, h = inner_h },
                TextWidget:new{
                    text = mandatory,
                    face = Font:getFace("infont", self.infont_size or 16),
                    fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
                },
            }
        end
        local hgroup = HorizontalGroup:new{ align = "center" }
        for i, w in ipairs(hgroup_items) do
            hgroup[i] = w
        end
        self._underline_container = UnderlineContainer:new{
            vertical_align = "top",
            padding = 0,
            dimen = dimen:copy(),
            linesize = 1,
            hgroup,
        }
        self[1] = self._underline_container
        return
    end

    local cover_w = math.floor(inner_h * 0.72)
    local border = Size.border.thin

    local cover_widget
    local cover_bb = entry.cover_bb
    if cover_bb and cover_bb.w > 0 and cover_bb.h > 0 then
        local scale = math.min(
            (cover_w - 2 * border) / cover_bb.w,
            (inner_h - 2 * border) / cover_bb.h
        )
        local img = ImageWidget:new{
            image = cover_bb,
            image_disposable = false,
            scale_factor = scale,
        }
        img:_render()
        cover_widget = CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = inner_h },
            FrameContainer:new{
                bordersize = border,
                padding = 0,
                dim = entry.dim,
                img,
            },
        }
    else
        cover_widget = CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = inner_h },
            FrameContainer:new{
                bordersize = border,
                padding = Size.padding.tiny,
                dim = entry.dim,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{
                        w = cover_w - 2 * border,
                        h = inner_h - 2 * border,
                    },
                    TextWidget:new{
                        text = "⛶",
                        face = Font:getFace("cfont", Screen:scaleBySize(18)),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    },
                },
            },
        }
    end

    local mandatory = entry.mandatory_func and entry.mandatory_func() or entry.mandatory
    local mandatory_w = 0
    if mandatory and mandatory ~= "" then
        mandatory_w = TextWidget:new{
            text = mandatory,
            face = Font:getFace("infont", self.infont_size or 16),
            fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
        }:getWidth() + Size.span.horizontal_default
    end

    local text_w = dimen.w - pad_h_left - cover_w - mandatory_w - Size.span.horizontal_default * 2
    local text_widget = TextBoxWidget:new{
        text = getMenuText(entry),
        face = Font:getFace("smallinfofont", self.font_size or 20),
        width = text_w,
        max_lines = 2,
        fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
        bold = entry.bold,
    }

    local text_container = CenterContainer:new{
        dimen = Geom:new{ w = text_w, h = inner_h },
        text_widget,
    }

    local hgroup_items = {
        HorizontalSpan:new{ width = pad_h_left },
        cover_widget,
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        text_container,
    }
    if mandatory and mandatory ~= "" then
        hgroup_items[#hgroup_items + 1] = RightContainer:new{
            dimen = Geom:new{ w = mandatory_w, h = inner_h },
            TextWidget:new{
                text = mandatory,
                face = Font:getFace("infont", self.infont_size or 16),
                fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
            },
        }
    end

    local hgroup = HorizontalGroup:new{ align = "center" }
    for i, w in ipairs(hgroup_items) do
        hgroup[i] = w
    end

    self._underline_container = UnderlineContainer:new{
        vertical_align = "top",
        padding = 0,
        dimen = dimen:copy(),
        linesize = 1,
        hgroup,
    }
    self[1] = self._underline_container
end

function ShelfMenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    return true
end

function ShelfMenuItem:onUnfocus()
    self._underline_container.color = self.line_color
    return true
end

function ShelfMenuItem:getGesPosition(ges)
    local dim = self[1].dimen
    return {
        x = (ges.pos.x - dim.x) / dim.w,
        y = (ges.pos.y - dim.y) / dim.h,
    }
end

function ShelfMenuItem:onTapSelect(_, ges)
    if not self[1].dimen then
        return
    end
    local pos = self:getGesPosition(ges)
    self.menu:onMenuSelect(self.entry, pos)
    return true
end

local ShelfMenu = Menu:extend{
    client = nil,
    plugin = nil,
}

function ShelfMenu:_recalculateDimen(no_recalculate_dimen)
    local row_h = COVER_ROW_HEIGHT
    if not no_recalculate_dimen then
        local top_height = 0
        if self.title_bar and not self.no_title then
            top_height = self.title_bar:getHeight()
        end
        local bottom_height = 0
        if self.page_return_arrow and self.page_info_text then
            bottom_height = math.max(
                self.page_return_arrow:getSize().h,
                self.page_info_text:getSize().h
            ) + Size.padding.button
        end
        self.available_height = self.inner_dimen.h - top_height - bottom_height
        self.perpage = math.max(1, math.floor(self.available_height / row_h))
        self.font_size = self.items_font_size or Menu.getItemFontSize(self.perpage)
        self.item_dimen = Geom:new{
            x = 0, y = 0,
            w = self.inner_dimen.w,
            h = row_h,
        }
        self.page_num = self:getPageNumber(#self.item_table)
        if self.page > self.page_num then
            self.page = self.page_num
        end
    end
end

function ShelfMenu:updateItems(select_number, no_recalculate_dimen)
    if self._cover_fetch_action then
        UIManager:unschedule(self._cover_fetch_action)
        self._cover_fetch_action = nil
    end
    self._cover_fetch_scheduled = false

    local old_dimen = self.dimen and self.dimen:copy()
    self.layout = {}
    self.item_group:clear()
    self:_recalculateDimen(no_recalculate_dimen)
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()

    local items_nb = self.perpage
    local idx_offset = (self.page - 1) * items_nb
    local need_fetch = false

    for idx = 1, items_nb do
        local index = idx_offset + idx
        local item = self.item_table[index]
        if item == nil then
            break
        end
        item.idx = index
        if index == self.itemnumber then
            select_number = idx
        end

        local book = item.book
        local book_id = bookIdOf(book)
        local cover_url = coverUrlOf(book)
        if not item.cover_bb and book_id and cover_url and cover_url ~= "" then
            item.cover_bb = CoverCache.loadCached(book_id)
            if not item.cover_bb then
                need_fetch = true
            end
        end

        local item_tmp = ShelfMenuItem:new{
            show_parent = self.show_parent,
            entry = item,
            menu = self,
            dimen = self.item_dimen:copy(),
            font_size = self.font_size,
            infont_size = self.items_mandatory_font_size or (self.font_size - 4),
            line_color = self.line_color,
        }
        table.insert(self.item_group, item_tmp)
        table.insert(self.layout, { item_tmp })
    end

    self:updatePageInfo(select_number)
    self:mergeTitleBarIntoLayout()

    UIManager:setDirty(self.show_parent, function()
        local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
        return "ui", refresh_dimen, true
    end)

    if need_fetch and self.client then
        self:_scheduleCoverFetch()
    end
end

function ShelfMenu:_scheduleCoverFetch()
    if self._cover_fetch_scheduled then
        return
    end
    self._cover_fetch_scheduled = true
    local fetch_page = self.page

    local items_nb = self.perpage
    local idx_offset = (fetch_page - 1) * items_nb
    local pending = {}
    for idx = 1, items_nb do
        local index = idx_offset + idx
        local item = self.item_table[index]
        local book = item and item.book
        local book_id = bookIdOf(book)
        local cover_url = coverUrlOf(book)
        if item and not item.cover_bb and book_id and cover_url and cover_url ~= "" then
            pending[#pending + 1] = item
        end
    end

    if #pending == 0 then
        self._cover_fetch_scheduled = false
        return
    end

    local updated = false
    local cursor = 1

    local function fetchNext()
        if self._cover_fetch_cancelled or not self.item_table or self.page ~= fetch_page then
            self._cover_fetch_scheduled = false
            return
        end

        if cursor > #pending then
            self._cover_fetch_scheduled = false
            if updated and self.page == fetch_page then
                self:updateItems(1, true)
            end
            return
        end

        local item = pending[cursor]
        cursor = cursor + 1

        local book = item and item.book
        local book_id = bookIdOf(book)
        local cover_url = coverUrlOf(book)
        if not item.cover_bb and book_id and cover_url and cover_url ~= "" then
            local bb = CoverCache.fetch(self.client, book_id, cover_url)
            if bb and bb.w > 0 and bb.h > 0 then
                item.cover_bb = bb
                updated = true
            end
        end

        UIManager:scheduleIn(0.05, fetchNext)
    end

    self._cover_fetch_action = fetchNext
    UIManager:scheduleIn(0.05, fetchNext)
end

function ShelfMenu:onCloseWidget()
    self._cover_fetch_cancelled = true
    if self._cover_fetch_action then
        UIManager:unschedule(self._cover_fetch_action)
        self._cover_fetch_action = nil
    end
    self._cover_fetch_scheduled = false
    self.item_group:free()
    Menu.onCloseWidget(self)
end

function ShelfMenu:onMenuSelect(item)
    if item.sub_item_table == nil then
        if item.select_enabled == false then
            return true
        end
        if item.select_enabled_func and not item.select_enabled_func() then
            return true
        end
        self:onMenuChoice(item)
    else
        self.item_table.title = self.title
        table.insert(self.item_table_stack, self.item_table)
        self:switchItemTable(item.text, item.sub_item_table)
    end
    return true
end

local ShelfUI = {}

function ShelfUI.show(opts)
    opts = opts or {}
    local plugin = opts.plugin
    local buildItems = opts.buildItems
    if not plugin or not buildItems then
        return nil
    end

    local items = buildItems()
    if not items or #items == 0 then
        if opts.onEmpty then
            opts.onEmpty()
        end
        return nil
    end

    local menu = ShelfMenu:new{
        client = plugin.client,
        plugin = plugin,
        title = opts.title or _("WeRead Bookshelf"),
        item_table = items,
        is_borderless = true,
        title_bar_fm_style = true,
        items_mandatory_font_size = 16,
    }
    UIManager:show(menu)
    return menu
end

return ShelfUI
