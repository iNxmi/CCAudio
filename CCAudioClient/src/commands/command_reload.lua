local Api = require("api")

local CommandRefresh = {}

CommandRefresh.NAME = "reload"

function CommandRefresh.register(parser)
    local command = parser:command(CommandRefresh.NAME, "Reload music list.")
    return command
end

function CommandRefresh.execute(arguments)
    Api.reload(arguments.address)
end

return CommandRefresh