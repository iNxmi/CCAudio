local Api = require("api")

local CommandList = {}

CommandList.NAME = "list"

function CommandList.register(parser)
    local command = parser:command(CommandList.NAME, "List music.")
    return command
end

function CommandList.execute(arguments)
    local list = Api.get_list(arguments.address)
    if list == nil then
        return
    end

    for index, media in ipairs(list) do
        if index % 2 == 0 then
            term.setTextColour(colors.red)
        else
            term.setTextColour(colors.green)
        end

        local message = string.format("%s%d. %s", string.rep(" ", #tostring(#list) - #tostring(index - 1)), index - 1, media.name)
        textutils.pagedPrint(message)

        term.setTextColour(colors.white)
    end
end

return CommandList