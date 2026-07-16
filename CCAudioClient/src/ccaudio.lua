local VERSION = "1.0.0-alpha"

function parser()
    local argparse = require "argparse__0_7_2"

    local parser = argparse("script", "Example Description.")

    function parser:error(message)
        error(message, 0)
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
local arguments = parser:parse(raw_arguments)

local address = string.format("%s:%d", arguments.address, arguments.port)
local http_url = string.format("http://%s", address)
local websocket_url = string.format("ws://%s", address)

function get_list()
    local url = string.format("%s/list", http_url)
    local request = http.get(url)
    local json_text, _ = request.readAll()
    return textutils.unserializeJSON(json_text)
end

function list()
    local list = get_list()
    for index, file in ipairs(list) do
        local message = string.format("%s%d. %s", string.rep(" ", #tostring(#list) - #tostring(index - 1)), index - 1, file)

        if index % 2 == 0 then
            term.setTextColour(colours.red)
            else
            term.setTextColour(colours.green)
        end

        textutils.pagedPrint(message)
    end
end

function play()
    local speaker = peripheral.find("speaker")

    if not speaker then
        error("No speaker found.")
    end

    local initialUrl = string.format("%s/request?file=%s&chunkSizeInBytes=%d", http_url, arguments.file, arguments.chunk_size)
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

    print("chunkCount: " .. chunk_count)

    local MAX_CHUNKS = math.floor(1000000 / chunk_size)
    local chunkBuffer = {}
    local nextDownloadIndex = 0
    local nextPlayIndex = 0

    local running = true
    local paused = false

    local function inputThread()
        while running do
            local event, key = os.pullEvent("key")

            if key == keys.q then
                running = false
                break
            elseif key == keys.p then
                paused = not paused
                if paused then
                    speaker.stop()
                    print("paused")
                else
                    print("Unpaused")
                end
            end
        end
    end

    local function downloadThread()
        while running do
            if nextDownloadIndex < chunk_count then
                if #chunkBuffer < MAX_CHUNKS then
                    local url = string.format("%s/stream?hash=%s&chunk=%d", http_url, hash, nextDownloadIndex)
                    local res, err = http.get(url, {}, true)

                    if res then
                        local jsonChunkText = res.readAll()
                        local currentChunk = textutils.unserializeJSON(jsonChunkText)
                        table.insert(chunkBuffer, currentChunk)
                        nextDownloadIndex = nextDownloadIndex + 1
                        res.close()
                    else
                        print("[ERROR] Could not fetch new data. " .. err)
                        sleep(0.5)
                    end
                else
                    sleep(0.1)
                end
            else
                -- download finished but we have to keep the thread alive because of WaitForAny()
                sleep(0.5)
            end
        end
    end

    local function audioThread()
        local chunkSizeLimit = 128 * 1024

        while running and nextPlayIndex < chunk_count do
            while paused and running do
                speaker.stop()
                sleep(0.1)
            end

            if #chunkBuffer > 0 then
                local tmpBuffer = table.remove(chunkBuffer, 1)
                nextPlayIndex = nextPlayIndex + 1

                for startIdx = 1, #tmpBuffer, chunkSizeLimit do
                    local audioBuffer = {}

                    while paused and running do
                        speaker.stop()
                        sleep(0.1)
                    end

                    for j = startIdx, math.min(startIdx + chunkSizeLimit - 1, #tmpBuffer) do
                        table.insert(audioBuffer, tmpBuffer[j])
                    end

                    if #audioBuffer > 0 then
                        while not speaker.playAudio(audioBuffer) and running do
                            local function bufferEmptyInterrupt()
                                os.pullEvent("speaker_audio_empty")
                            end
                            local function pauseInterrupt()
                                while not paused and running do
                                    sleep(0.05)
                                end
                            end
                            parallel.waitForAny(bufferEmptyInterrupt, pauseInterrupt)
                            while paused do
                                speaker.stop()
                                sleep(0.1)
                            end
                        end
                    end
                end
            else
                sleep(0.05)
            end
        end
        running = false
    end

    parallel.waitForAny(audioThread, inputThread, downloadThread)
end

function echo()
    local url = string.format("%s/echo", websocket_url)
    local socket = assert(http.websocket(url))

    socket.send(arguments.message)
    local response, is_binary = socket.receive()
    socket.close()

    print(response)
end

function get_command()
    if arguments.list then
        return list
    elseif arguments.play then
        return play
    elseif arguments.echo then
        return echo
    end
end

function execute()
    if arguments.version then
        print(VERSION)
    end

    if arguments.print_arguments then
        print(textutils.serialize(raw_arguments))
        print(textutils.serialize(arguments))
    end

    local command = get_command()
    return command()
end

local result = execute()