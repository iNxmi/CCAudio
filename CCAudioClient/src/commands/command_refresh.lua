local api = require("api")

local CommandList = {}
local CommandList_mt = { __index = CommandList }

function CommandList.new()
    local self = {}
    setmetatable(self, CommandList_mt)
    return self
end

function CommandList:register(parser)
    parser:command("list", "List music.")
end

function CommandList:execute(arguments)
    local list = api.fetch_list(arguments.address)
    for index, file in ipairs(list) do
        local message = string.format("%s%d. %s", string.rep(" ", #tostring(#list) - #tostring(index - 1)), index - 1, file)

        if index % 2 == 0 then
            term.setTextColour(colors.red)
        else
            term.setTextColour(colors.green)
        end

        textutils.pagedPrint(message)

        term.setTextColour(colors.white)
    end
end

return CommandList