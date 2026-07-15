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

local ADDRESS = "127.0.0.1:8080"
local HTTP_URL = "http://" .. ADDRESS
local WEBSOCKET_URL = "ws://" .. ADDRESS

local raw_arguments = { ... }

local parser = parser()
local parsed_arguments = parser:parse(raw_arguments)

local address = string.format("%s:%d", parsed_arguments.address, parsed_arguments.port)
local http_url = string.format("http://%s", address)
local websocket_url = string.format("ws://%s", address)

function list()
    local url = string.format("%s/list", http_url)
    local request, err = http.get(url)
    if not request then
        error("HTTP request failed: " .. tostring(err))
        return
    end
    local json_text, _ = request.readAll()
    local json = textutils.unserializeJSON(json_text)

    for index, file in ipairs(json) do
        local message = string.format("%d. %s", index, file)
        print(message)
    end
end

function play()
    local speaker = peripheral.find("speaker")

    if not speaker then
        error("No speaker found.")
    end

    local initialUrl = string.format("%s/request?file=%s&chunkSizeInBytes=%d", http_url, parsed_arguments.file, parsed_arguments.chunk_size)
    local request, err = http.get(initialUrl)
    if not request then
        error("HTTP request failed: " .. tostring(err))
        return
    end

    local json_text, _ = request.readAll()
    local json = textutils.unserializeJSON(json_text)

    local chunk_size = json.chunk_size_in_bytes
    local chunk_count = json.number_of_chunks
    local hash = json.hash

    local bufferedChunks = 0
    local MAX_CHUNKS = math.floor(1000000 / chunk_size)
    local dataBuffer = {}
    local nextDownloadIndex = 0

    for i = 0, chunk_count - 1, 1 do

        while ((bufferedChunks <= MAX_CHUNKS) and not (nextDownloadIndex >= chunk_count)) do
            local url = string.format("%s/stream?hash=%s&chunk=%d",HTTP_URL, hash, nextDownloadIndex)
            local res, _ = http.get(url, {}, true)

            local jsonChunkText = res.readAll()
            local currentChunk = textutils.unserializeJSON(jsonChunkText)

            nextDownloadIndex = nextDownloadIndex + 1
            table.insert(dataBuffer, currentChunk)
            bufferedChunks = bufferedChunks + 1
            res.close()

        end

        -- play the audio
        local tmpBuffer = table.remove(dataBuffer, 1)
        bufferedChunks = bufferedChunks - 1

        if tmpBuffer then
            local audioBuffer = {}

            local chunkSizeLimit = 128 * 1024
            for startIdx = 1, #tmpBuffer, chunkSizeLimit do
                local audioBuffer = {}

                for j = startIdx, math.min(startIdx + chunkSizeLimit - 1, #tmpBuffer) do
                    table.insert(audioBuffer, tmpBuffer[j])
                end

                if #audioBuffer > 0 then
                    while not speaker.playAudio(audioBuffer) do
                        os.pullEvent("speaker_audio_empty")
                    end
                end
            end
        end
    end
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