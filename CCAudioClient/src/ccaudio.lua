_G.CONSTANTS = require("constants")

local Parser = require("parser")
local parser = Parser.new()

local CommandList = require("commands/command_list")
local command_list = CommandList.new()
parser:register_command(command_list)

local CommandPlay = require("commands/command_play")
local command_play = CommandPlay.new()
parser:register_command(command_play)

local function checksum(list)
    local sum = 0
    for _, value in ipairs(list) do
        sum = sum + value
    end
    return sum
end

local raw_arguments = { ... }
local arguments = parser:parse(raw_arguments)

local function get_command()
    if arguments.list then
        return command_list
    elseif arguments.play then
        return command_play
    end
end

local function execute()
    if arguments.version then
        print(CONSTANTS.VERSION)
    end

    if arguments.print_arguments then
        print(textutils.serialize(raw_arguments))
        print(textutils.serialize(arguments))
    end

    local command = get_command()
    return command:execute(arguments)
end

local result = execute()