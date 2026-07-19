local Api = require("api")

local CommandRefresh = {}

CommandRefresh.NAME = "refresh"

function CommandRefresh.register(parser)
    local command = parser:command(CommandRefresh.NAME, "Refresh music list.")
    return command
end

function CommandRefresh.execute(arguments)
    Api.refresh(arguments.address)
end

return CommandRefresh