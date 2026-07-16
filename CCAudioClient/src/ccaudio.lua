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
local http_url_default = string.format("http://%s", address)

function get_list()
    local url = string.format("%s/list", http_url_default)
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

function fetch(url)
    local response, err = http.get(url)
    if not response then
        error("HTTP request failed: " .. tostring(err))
        return
    end

    local json_text, _ = response.readAll()
    local json = textutils.unserializeJSON(json_text)

    return json
end

function request(http_url, index, chunk_size)
    local url = string.format("%s/request?file=%s&chunkSizeInBytes=%d", http_url, index, chunk_size)
    return fetch(url)
end

function stream(http_url, hash, index)
    local url = string.format("%s/stream?hash=%s&chunk=%d", http_url, hash, index)
    return fetch(url)
end

function play()
    local speaker = peripheral.find("speaker")
    if not speaker then
        error("No speaker found.")
        return
    end

    local json = request(http_url_default, arguments.file, arguments.chunk_size)

    local chunk_size = json.chunk_size_in_bytes
    local chunk_count = json.number_of_chunks
    local hash = json.hash

    local AVAILABLE_MEMORY = 1000000
    local sampleBuffer = {}
    local nextDownloadIndex = 0
    local finishedDownload = false

    local running = true
    local paused = false

    local time = 0

    local speakerBuffer = {}

    local function timerThread()
        local timerID = os.startTimer(0.1)

        while running do
            local event, param = os.pullEvent()

            if event == "timer" and param == timerID then
                if not paused then
                    time = time + 1
                    local total_seconds = time / 10
                    local x, y = term.getCursorPos()
                    --term.setCursorPos(1, 50)
                    --term.clearLine()
                    --write(string.format("time: %.1fs", total_seconds))
                    --term.setCursorPos(x, y)

                    local samplesPerStep = 48000 * 0.1
                    if (#speakerBuffer < samplesPerStep) then
                        speakerBuffer = { }
                    else
                        local temp = {}
                        table.move(speakerBuffer, samplesPerStep + 1, #speakerBuffer, 1, temp)
                        speakerBuffer = temp
                    end
                end
                timerID = os.startTimer(0.1)
            elseif event == "resume" then
                timerID = os.startTimer(0.1)
            end
        end
    end

    local function inputThread()
        while running do
            local _, key = os.pullEvent("key")

            if key == keys.q then
                running = false
                speaker.stop()
                break
            elseif key == keys.p then
                paused = not paused
                if paused then
                    print(" paused")
                    os.queueEvent("paused")
                    speaker.stop()
                else
                    os.queueEvent("resume")
                    print(" Unpaused")
                end
            end

            sleep(0.05)
        end
    end

    local function downloadThread()
        while running do
            if nextDownloadIndex < chunk_count then
                if #sampleBuffer < AVAILABLE_MEMORY then
                    local currentChunk = stream(http_url_default, hash, nextDownloadIndex)
                    if currentChunk then
                        table.move(currentChunk, 1, #currentChunk, #sampleBuffer + 1, sampleBuffer) -- appends the current to sampleBuffer
                        nextDownloadIndex = nextDownloadIndex + 1
                    else
                        print("[ERROR] Could not fetch new data. " .. err)
                        sleep(0.5)
                    end
                else
                    sleep(0.1)
                end
            else
                -- download finished but we have to keep the thread alive because of WaitForAny()
                if not finishedDownload then
                    finishedDownload = true
                end
                sleep(1)
            end
        end
    end

    local function audioThread()
        -- ############ constants ##############
        local SPEAKER_BUFFER_SIZE = 64 * 1024 -- 128KB
        -- #####################################

        while running do
            -- determine if song is finished
            if #sampleBuffer == 0 and finishedDownload then
                running = false
                break
            end

            if #sampleBuffer > 0 then
                -- fill audioBuffer with values
                local audioBuffer = {}
                local endIDx = math.min(#sampleBuffer, SPEAKER_BUFFER_SIZE)
                table.move(sampleBuffer, 1, endIDx, 1, audioBuffer)

                -- sending the buffer to the speaker
                ::beginPlay::
                local beginPlayTime = 0
                local success = false
                while not success do
                    print("while")
                    print(time)
                    success = speaker.playAudio(audioBuffer)
                    if success then
                        beginPlayTime = time
                        --table.move(audioBuffer, 1, #audioBuffer, #speakerBuffer + 1, speakerBuffer) -- appends audioBuffer to speakerBuffer
                    else
                        local function bufferEmptyInterrupt()
                            os.pullEvent("speaker_audio_empty")
                        end
                        local function pauseInterrupt()
                            os.pullEvent("paused")
                        end
                        local function resumeInterrupt()
                            os.pullEvent("resume")
                        end

                        parallel.waitForAny(bufferEmptyInterrupt, pauseInterrupt)

                        if paused then
                            speaker.stop()
                            local pauseTime = time
                            os.pullEvent("resume")
                            print("resume")
                            local playedSamples = (pauseTime - beginPlayTime) * (48000 / 10)

                            -- removed the played samples from audioBuffer
                            --local temp = {}
                            --table.move(audioBuffer, playedSamples + 1, #audioBuffer, 1, temp)
                            --audioBuffer = temp
                            goto beginPlay
                        end
                    end
                end

                -- remove what we put in audioBuffer from sampleBuffer
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

    parallel.waitForAny(audioThread, inputThread, downloadThread, timerThread)
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