_G.CONSTANTS = require("constants")

local Parser = require("parser")
local parser = Parser.new()

local commands = {
    require("commands/command_list"),
    require("commands/command_refresh"),
    require("commands/command_play")
}

for _, command in ipairs(commands) do
    parser:register_command(command)
end

local function checksum(list)
    local sum = 0
    for _, value in ipairs(list) do
        sum = sum + value
    end
    return sum
end

local raw_arguments = { ... }
local arguments, command = parser:parse(raw_arguments)

local function execute()
    if arguments.version then
        print(CONSTANTS.VERSION)
    end

    if arguments.print_arguments then
        print(textutils.serialize(raw_arguments))
        print(textutils.serialize(arguments))
    end

    return command.execute(arguments)
end

local result = execute()