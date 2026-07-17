local instance = {}

local api = require("../api/api")

function instance.get_command(argparse_command)

end

function instance.execute()
    local list = api.fetch_list(http_url_default)
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

return instance