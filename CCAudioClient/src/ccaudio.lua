function parser()
    local argparse = require "argparse__0_7_2"

    local parser = argparse("script", "Example Description.")

    function parser:error(message)
        error(message,0)
    end

    local parser_help = parser.help
    function parser:help(...)
        local help = parser_help(self, ...)
        error(help, 0)
    end

    parser:flag("--print_arguments", "print debug argument info")

    local command_list = parser:command("list", "List music.")
    local command_play = parser:command("play", "Play music.")
    local command_echo = parser:command("echo", "Test the WebSocket with echo.")
    command_echo:argument("message", "Message to send the echo.")
    --command_play:arguments("file", "The file to start playing.")

    return parser
end

local ADDRESS = "127.0.0.1:8080"
local HTTP_URL = "http://" .. ADDRESS
local WEBSOCKET_URL = "ws://" .. ADDRESS

local raw_arguments = { ... }

local parser = parser()
local parsed_arguments = parser:parse(raw_arguments)

function list()
    local url = string.format("%s/list", HTTP_URL)
    local raw_json, is_binary = http.get(url)
    local json = textutils.unserialize(raw_json)

    for index, file in ipairs(json) do
        local message = string.format("%d. $s", index, file)
        print(message)
    end
end

function play()

end

function echo()
    local url = string.format("%s/echo", WEBSOCKET_URL)
    local socket = assert(http.websocket(url))

    socket.send(parsed_arguments.message)
    local response, is_binary = socket.receive()
    socket.close()

    print(response)
end

function get_command()
    if parsed_arguments.list then
        return list
    elseif parsed_arguments.play then
        return play
    elseif parsed_arguments.echo then
        return echo
    end
end

local command = get_command()

if parsed_arguments.print_arguments then
    print(textutils.serialize(raw_arguments))
    print(textutils.serialize(parsed_arguments))
end

local result = command()