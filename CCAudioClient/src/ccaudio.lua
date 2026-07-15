local VERSION = "1.0.0-alpha"

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
    parser:flag("--version", "print version")

    parser:option("-a --address", "set server address", "127.0.0.1")
    parser:option("-p --port", "set server port", "8080")

    local command_list = parser:command("list", "List music.")

    local command_play = parser:command("play", "Play music.")
    command_play:argument("file", "File to play.")
    command_play:option("-c --chunk_size", "Chunk size (in bytes)", 128 * 1024)

    local command_echo = parser:command("echo", "Test the WebSocket with echo.")
    command_echo:argument("message", "Message to send the echo.")

    return parser
end

local raw_arguments = { ... }

local parser = parser()
local parsed_arguments = parser:parse(raw_arguments)

local address = string.format("%s:%d", parsed_arguments.address, parsed_arguments.port)
local http_url = string.format("http://%s", address)
local websocket_url = string.format("ws://%s", address)

function list()
    local url = string.format("%s/list", http_url)
    local request = http.get(url)
    local json_text, _ = request.readAll()
    local json = textutils.unserializeJSON(json_text)

    for index, file in ipairs(json) do
        local message = string.format("%d. %s", index, file)
        print(message)
    end
end

function play()
    local url = string.format("%s/request?file=%s&chunkSizeInBytes=%d", http_url, parsed_arguments.file, parsed_arguments.chunk_size)
    local request = http.get(url)
    local json_text, _ = request.readAll()
    local json = textutils.unserializeJSON(json_text)

    for index = 0, json.number_of_chunks - 1 do
        local url_stream = string.format("%s/stream?hash=%s&chunk=%d", http_url,json.hash, index)
        local request_stream = http.get(url_stream)
        local chunk, _ = request_stream.readAll()
    end

    print("done")
end

function echo()
    local url = string.format("%s/echo", websocket_url)
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

function execute()
    if parsed_arguments.version then
        print(VERSION)
    end

    if parsed_arguments.print_arguments then
        print(textutils.serialize(raw_arguments))
        print(textutils.serialize(parsed_arguments))
    end

    if parsed_arguments.address then
        print(textutils.serialize(raw_arguments))
    end

    local command = get_command()
    return command()
end

local result = execute()