
local graphics = {}

local canvas = nil
local mode = 0 -- 0 basic mode, 1 advanced mode

-- frame buffer
-- graphicsapi different modes, either framebuffer mde, when you draw it get's drawn in buffer and then buffer swapped when render() function called or basic mode, where it just draws on the target


local last_text_color = nil
local last_background_color = nil

function graphics.set_target(canvas_obj)
    canvas = canvas_obj
end

function graphics.get_target()
    return canvas
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

function graphics.get_dimensions(target)
    target = target or canvas or term.current()
    return target.getSize()
end

function graphics.clear(color, target)
    target = target or canvas or term.current()
    color = color or target.getBackgroundColor()
    if last_background_color ~= color then
        target.setBackgroundColor(color)
        last_background_color = color
    end
    target.clear()
end

function graphics.draw_pixel(x, y, color, target)
    target = target or canvas or term.current()
    color = color or target.getTextColor()
    x = math.max(x, 0)
    y = math.max(y, 0)
    if last_background_color ~= color then
        target.setBackgroundColor(color)
        last_background_color = color
    end

    target.setCursorPos(x,y)
    target.write(" ")
end

function graphics.draw_line(start_pos, end_pos, color, width, target)
    color = color or colors.white
    width = width or 1
    target = target or canvas or term.current()


end

function graphics.draw_rectangle_fill(x, y, width, height,  color, target)
    target = target or canvas or term.current()
    x = math.max(x, 0)
    y = math.max(y, 0)
end

function graphics.draw_rectangle_border(x, y, color, width, height, target)
    target = target or canvas or term.current()
    x = math.max(x, 0)
    y = math.max(y, 0)
end

function graphics.draw_circle_fill(x, y, width, height, color, target)
    target = target or canvas or term.current()
    x = math.max(x, 0)
    y = math.max(y, 0)
end

function graphics.draw_circle_border(x, y, width, height, color, target)
    target = target or canvas or term.current()
    x = math.max(x, 0)
    y = math.max(y, 0)
end

function graphics.draw_text(x, y, text, text_color, background_color, target)
    target = target or canvas or term.current()
    text_color = text_color or colors.white
    background_color = background_color or colors.black
    x = math.max(x, 0)
    y = math.max(y, 0)
    if text_color ~= last_text_color then
        target.setTextColor(text_color)
        last_text_color = text_color
    end
    if last_background_color ~= background_color then
        target.setBackgroundColor(background_color)
        last_background_color = background_color
    end
    target.setCursorPos(x, y)
    target.write(text)
end

function graphics.draw_sprite(x_pos, y_pos, data, target)
    target = target or canvas or term.current()
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
    last_background_color = nil
    last_text_color = nil
end


return graphics