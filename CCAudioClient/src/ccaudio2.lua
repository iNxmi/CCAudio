local VERSION = "1.0.0-alpha"

local MAXIMUM_MEMORY_USAGE = 0.90
local AVAILABLE_MEMORY = 1000000 * MAXIMUM_MEMORY_USAGE

local SPEAKER_BUFFER_SIZE = 8 * 1024

local SAMPLES_PER_SECOND = 48000

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

function seconds()
    return os.epoch("utc") / 1000
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

function play()
    local speaker = peripheral.find("speaker")
    if not speaker then
        error("No speaker found.")
        return
    end

    local json = fetch_request(http_url_default, arguments.file, arguments.chunk_size)
    print(textutils.serializeJSON(json))

    local sampleBuffer = {}

    local download_index = 0

    local is_running = true
    local is_paused = false
    local should_update = false

    local time_last = 0
    local time_delta = 0
    local time_audio = 0

    local chunks = {}

    function input()
        os.startTimer(0)
        local event = {os.pullEvent()}
        if event[1] ~= "key" then
            return
        end

        local hold = event[3]
        if hold then
            return
        end

        local key = event[2]
        if key == keys.q then
            is_running = false
            speaker.stop()
        elseif key == keys.p or key == keys.space then
            is_paused = not is_paused
            if is_paused then
                speaker.stop()
                print("paused")
            else
                should_update = true
                print("unpaused")
            end
        elseif key == 205 then
            time_audio = time_audio + 10
            should_update = true
        elseif key == 203 then
            time_audio = time_audio - 10
            should_update = true
        end
    end

    function download()
        if download_index >= json.number_of_chunks then
            return
        end

        if #sampleBuffer >= AVAILABLE_MEMORY then
            return
        end

        if chunks[download_index] ~= nil then
            return
        end

        local chunk = fetch_stream(http_url_default, json.hash, download_index)
        if not chunk then
            return
        end

        chunks[download_index] = chunk
        download_index = download_index + 1
    end

    -- index_global_samples_start   starting from 1
    -- index_global_samples_start   is inclusive
    -- index_global_samples_end     is inclusive
    function get_samples(index_global_samples_start, index_global_samples_end)
        local samples = {}

        local index_chunk_start = math.floor(index_global_samples_start / SAMPLES_PER_SECOND)
        local index_chunk_end = math.ceil(index_global_samples_end / SAMPLES_PER_SECOND)

        for index = index_chunk_start, index_chunk_end do
            local chunk = chunks[index]
            table.move(chunk, 1, #chunk, 1, samples)
        end

        local index_global_samples_length = index_global_samples_end - index_global_samples_start
        local index_normalized_samples_start = index_global_samples_start % SAMPLES_PER_SECOND
        local index_normalized_samples_end = index_normalized_samples_start + index_global_samples_length
        return unpack(samples, index_normalized_samples_start, index_normalized_samples_end)
    end

    function audio()
        if is_paused then
            return
        end

        time_audio = time_audio + time_delta
        print(time_audio)

        if #sampleBuffer <= 0 then
            is_running = not (download_index >= json.number_of_chunks - 1)
            return
        end

        local speakerBuffer = {}

        local index_end = math.min(#sampleBuffer, SPEAKER_BUFFER_SIZE)
        local index_start = 1
        if should_update then
            local chunk = math.floor((time_audio * SAMPLES_PER_SECOND) / SPEAKER_BUFFER_SIZE)
            local playedSamples = (time_audio * SAMPLES_PER_SECOND) % SPEAKER_BUFFER_SIZE
            index_start = math.floor(playedSamples)
        end

        table.move(sampleBuffer, index_start, index_end, 1, speakerBuffer)

        local success = speaker.playAudio(speakerBuffer)
        if not success then
            return
        end

        --local sum = 0
        --for _, value in ipairs(speakerBuffer) do
        --    sum = sum + value
        --end
        --print(sum)

        if not should_update then
            local temp = {}
            table.move(sampleBuffer, index_end + 1, #sampleBuffer, 1, temp)
            sampleBuffer = temp
        end

        should_update = false
    end

    time_last = seconds()
    while is_running do
        local time_current = seconds()
        time_delta = time_current - time_last
        time_last = time_current

        input()
        download()
        audio()
    end
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