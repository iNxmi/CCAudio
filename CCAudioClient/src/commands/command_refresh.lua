local Api = require("api")

local CommandRefresh = {}
local CommandRefresh_mt = { __index = CommandRefresh }

function CommandRefresh.new()
    local self = {}
    setmetatable(self, CommandRefresh_mt)
    return self
end

function CommandRefresh:register(parser)
    parser:command("refresh", "Refresh music list.")
end

function CommandRefresh:execute(arguments)
    Api.refresh(arguments.address)
end

return CommandRefresh