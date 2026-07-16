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

    return parser
end

function fetch(url)
    local response, err = http.get(url)
    if not response then
        error("HTTP request failed: " .. tostring(err))
        return nil
    end

    local json_text, _ = response.readAll()
    local json = textutils.unserializeJSON(json_text)

    return json
end

function fetch_list(http_url)
    local url = string.format("%s/list", http_url)
    return fetch(url)
end

function fetch_request(http_url, index, chunk_size)
    local url = string.format("%s/request?file=%s&chunkSizeInBytes=%d", http_url, index, chunk_size)
    return fetch(url)
end

function fetch_stream(http_url, hash, index)
    local url = string.format("%s/stream?hash=%s&chunk=%d", http_url, hash, index)
    return fetch(url)
end

local raw_arguments = { ... }

local parser = parser()
local arguments = parser:parse(raw_arguments)

local address = string.format("%s:%d", arguments.address, arguments.port)
local http_url_default = string.format("http://%s", address)

function list()
    local list = fetch_list(http_url_default)
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

local AVAILABLE_MEMORY = 1000000 * 0.90
local SPEAKER_BUFFER_SIZE = 8 * 1024
function play()
    local speaker = peripheral.find("speaker")
    if not speaker then
        error("No speaker found.")
        return
    end

    local json = fetch_request(http_url_default, arguments.file, arguments.chunk_size)
    local chunk_size = json.chunk_size_in_bytes
    local chunk_count = json.number_of_chunks
    local hash = json.hash

    local sampleBuffer = {}
    local finishedDownload = false

    local running = true
    local paused = false

    local function thread_input()
        while running do
            local _, key = os.pullEvent("key")

            if key == keys.q then
                running = false
                speaker.stop()
                break
            elseif key == keys.p or key == keys.space then
                paused = not paused
                if paused then
                    print(" pause queued")
                else
                    print(" unpause queued")
                end
            end

            sleep(0.05)
        end
    end

    local function thread_download()
        local index = 0
        while index < chunk_count do
            if #sampleBuffer >= AVAILABLE_MEMORY then
                sleep(0.05)
                goto continue
            end

            local chunk = fetch_stream(http_url_default, hash, index)
            if chunk then
                table.move(chunk, 1, #chunk, #sampleBuffer + 1, sampleBuffer) -- appends the current to sampleBuffer
                index = index + 1
            else
                sleep(0.5)
            end

            ::continue::
        end
    end

    local function thread_audio()
        while running do

            if #sampleBuffer == 0 and finishedDownload then
                running = false
                break
            end

            if #sampleBuffer > 0 then
                local audioBuffer = {}
                local endIDx = math.min(#sampleBuffer, SPEAKER_BUFFER_SIZE)
                table.move(sampleBuffer, 1, endIDx, 1, audioBuffer)

                local success = false
                while not success do
                    success = speaker.playAudio(audioBuffer)
                    if not success then
                        sleep(0.05)
                        goto continue
                    end

                    local sum = 0
                    for index, value in ipairs(audioBuffer) do
                        sum = sum + value
                    end
                    print(sum)

                    local function bufferEmptyInterrupt()
                        os.pullEvent("speaker_audio_empty")
                    end
                    local function pauseInterrupt()
                        while not paused do
                            sleep(0.05)
                        end
                    end
                    parallel.waitForAny(bufferEmptyInterrupt, pauseInterrupt)

                    if paused then
                        speaker.stop()
                        while paused do
                            sleep(0.05)
                        end
                        success = false
                        print(" unpaused")
                    end

                    :: continue ::
                end

                if (endIDx == #sampleBuffer) then
                    sampleBuffer = {}
                else
                    local temp = {}
                    table.move(sampleBuffer, endIDx + 1, #sampleBuffer, 1, temp)
                    sampleBuffer = temp
                end
            else
                sleep(0.05)
            end
        end
    end

    function launch_audio()
        parallel.waitForAll(thread_audio)
    end

    function launch_input()

    end

    function launch_download()

    end

    parallel.waitForAll(thread_audio, thread_input) --thread_download
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