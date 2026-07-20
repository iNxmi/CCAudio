
local graphics = {}

local global_target = nil
local mode = 1 -- 0 basic mode, 1 performance mode

local framebuffer = nil

local last_text_color = nil
local last_background_color = nil
local last_cursor_pos_x, last_cursor_pos_y = nil, nil

function graphics.set_target(canvas_obj)
    global_target = canvas_obj
    framebuffer = nil
end

function graphics.get_target()
    return global_target
end

function graphics.set_mode(value)
    if value > 1 or value < 0 then
        return
    end
    mode = value
end

function graphics.get_mode()
    return mode
end

local function internal_create_framebuffer()
    global_target = global_target or term.current()
    local width, height = global_target.getSize()
    framebuffer = window.create(global_target, 1, 1, width, height, false)
    last_text_color = nil
    last_background_color = nil
    last_cursor_pos_y, last_cursor_pos_x = nil, nil
end

local function internal_get_correct_target(target)
    if mode == 0 then
        target = target or global_target or term.current()
        return target
    end
    if mode == 1 then
        if not framebuffer then
            internal_create_framebuffer()
        end
        return framebuffer
    end
end

local function internal_check_background_color(bg_color, target)
    if last_background_color ~= bg_color then
        target.setBackgroundColor(bg_color)
        last_background_color = bg_color
    end
end

local function internal_check_text_color(text_color, target)
    if last_text_color ~= text_color then
        target.setTextColor(text_color)
        last_text_color = text_color
    end
end

local function internal_check_cursor_pos(x, y, target)
    if last_cursor_pos_x ~= x or last_cursor_pos_y ~= y then
        target.setCursorPos(x,y)
        last_cursor_pos_x, last_cursor_pos_y = x, y
    end
end

function graphics.get_dimensions(target)
    target = internal_get_correct_target(target)
    return target.getSize()
end

function graphics.render()
    if mode ~= 1 then
        return
    end

    framebuffer.setVisible(true)
    framebuffer.setVisible(false)
end

function graphics.clear(color, target)
    target = internal_get_correct_target(target)
    color = color or target.getBackgroundColor()
    internal_check_background_color(color, target)
    target.clear()
    last_cursor_pos_x = nil
    last_cursor_pos_y = nil
end

function graphics.draw_pixel(x, y, color, target)
    target = internal_get_correct_target(target)
    color = color or target.getTextColor()
    x = math.max(x, 0)
    y = math.max(y, 0)
    internal_check_background_color(color, target)
    internal_check_cursor_pos(x, y, target)

    target.write(" ")

    last_cursor_pos_x = x + 1
end

function graphics.draw_line(start_pos, end_pos, color, width, target)
    color = color or colors.white
    width = width or 1
    target = internal_get_correct_target(target)


end

function graphics.draw_rectangle_fill(x, y, width, height,  color, target)
    graphics.draw_line(x, y, color, width, target)
end

function graphics.draw_rectangle_border(x, y, color, width, height, target)
    target = internal_get_correct_target(target)
    x = math.max(x, 0)
    y = math.max(y, 0)
end

function graphics.draw_circle_fill(x, y, width, height, color, target)
    target = internal_get_correct_target(target)
    x = math.max(x, 0)
    y = math.max(y, 0)
end

function graphics.draw_circle_border(x, y, width, height, color, target)
    target = internal_get_correct_target(target)
    x = math.max(x, 0)
    y = math.max(y, 0)
end

function graphics.draw_text(x, y, text, text_color, background_color, target)
    target = internal_get_correct_target(target)
    text_color = text_color or colors.white
    background_color = background_color or colors.black
    x = math.max(x, 0)
    y = math.max(y, 0)
    internal_check_text_color(text_color, target)
    internal_check_background_color(background_color, target)
    internal_check_cursor_pos(x, y, target)

    target.write(text)
    last_cursor_pos_x = x + #text
end

function graphics.draw_text_centered(x, y, text, text_color, background_color, target)
    graphics.draw_text(x - (#text / 2) + 1, y, text, text_color, background_color, target)
end

function graphics.draw_sprite(x_pos, y_pos, data, target)
    target = internal_get_correct_target(target)
    x_pos = math.max(x_pos, 0)
    y_pos = math.max(y_pos, 0)

    for y = 1, #data do
        local row = data[y]
        local width = #row

        target.setCursorPos(x_pos, y_pos + y - 1)

        local text = string.rep(" ", width)

        local fg_colors = string.rep("0", width)

        local bg_colors = ""
        for x = 1, #row do
            bg_colors = bg_colors .. colors.toBlit(row[x])
        end

        target.blit(text, fg_colors, bg_colors)
    end
    last_text_color = nil
    last_background_color = nil
    last_cursor_pos_y, last_cursor_pos_x = nil, nil
end

-- only works in basic mode
function graphics.print(...)
    local target = internal_get_correct_target(nil)
    -- print(target)
    local bg_color = target.getBackgroundColor()
    local fg_color = target.getTextColor()
    internal_check_background_color(bg_color, target)
    internal_check_text_color(fg_color, target)
    local _, height = target.getSize()
    local x, y = target.getCursorPos()

    local args = table.pack(...)
    local output_str = ""
    for i = 1, args.n do
        output_str = output_str .. tostring(args[i])
        if i < args.n then
            output_str = output_str .. " " -- Leerzeichen zwischen Argumenten
        end
    end

    internal_check_cursor_pos(x, y, target)
    target.write(output_str)

    if y >= height then
        target.scroll(1)
        x = 1
    else
        x = 1
        y = y + 1
    end
    internal_check_cursor_pos(x, y, target)
end

function graphics.set_background_color(color, target)
    target = internal_get_correct_target(target)
    internal_check_background_color(color, target)
end

function graphics.set_text_color(color, target)
    target = internal_get_correct_target(target)
    internal_check_text_color(color, target)
end
-- ------------------------

return graphics