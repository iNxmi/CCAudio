local VERSION = "1.0.0-alpha"

local MAXIMUM_MEMORY_USAGE = 0.90
local AVAILABLE_MEMORY = 1000000 * MAXIMUM_MEMORY_USAGE

local SKIP_AMOUNT = 3
local NEW_CHUNKS_PERCENTAGE = 0.7

local SPEAKER_BUFFER_SIZE = 64 * 1024

local SAMPLES_PER_SECOND = 48000

local function get_parser()
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

local function seconds()
    return os.epoch("utc") / 1000
end

local function fetch(url)
    local response, err = http.get(url)
    if not response then
        error("HTTP request failed: " .. tostring(err))
        return nil
    end

    local json_text, _ = response.readAll()
    local json = textutils.unserializeJSON(json_text)

    return json
end

local function fetch_list(http_url)
    local url = string.format("%s/list", http_url)
    return fetch(url)
end

local function fetch_request(http_url, index, chunk_size)
    local url = string.format("%s/request?file=%s&chunkSizeInBytes=%d", http_url, index, chunk_size)
    return fetch(url)
end

local function fetch_stream(http_url, hash, index)
    local url = string.format("%s/stream?hash=%s&chunk=%d", http_url, hash, index)
    return fetch(url)
end

local function checksum(list)
    local sum = 0
    for _, value in ipairs(list) do
        sum = sum + value
    end
    return sum
end

local raw_arguments = { ... }

local parser = get_parser()
local arguments = parser:parse(raw_arguments)

local address = string.format("%s:%d", arguments.address, arguments.port)
local http_url_default = string.format("http://%s", address)

local function command_list()
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

local function command_play()
    local speaker = peripheral.find("speaker")
    if not speaker then
        error("No speaker found.")
        return
    end

    local json = fetch_request(http_url_default, arguments.file, arguments.chunk_size)

    local is_running = true
    local is_paused = false
    local should_update = false

    local time_last = 0
    local time_delta = 0
    local time_audio = 0

    local volume = 1

    local index_samples_last = 0

    local chunks = {}

    local function input()
        while true do
            local event = {os.pullEvent("key")}
            local hold = event[3]
            local key = event[2]

            if event[1] ~= "key" then
                goto continue3
            end

            if hold then
                goto continue3
            end

            if key == keys.q then
                is_running = false
                speaker.stop()
            elseif key == keys.p or key == keys.space then
                is_paused = not is_paused
                if is_paused then
                    speaker.stop()
                    print("paused; time_audio="..time_audio)
                else
                    should_update = true
                    print("unpaused")
                end
            elseif key == keys.right then
                time_audio = time_audio + SKIP_AMOUNT
                speaker.stop()
                should_update = true
                print("time_audio="..time_audio)
            elseif key == keys.left then
                time_audio = time_audio - SKIP_AMOUNT
                speaker.stop()
                should_update = true
                print("time_audio="..time_audio)
            elseif key == keys.up then
                volume = volume + 0.1
                speaker.stop()
                should_update = true
                print("volume="..volume)
            elseif key == keys.down then
                volume = volume - 0.1
                speaker.stop()
                should_update = true
                print("volume="..volume)
            end
            ::continue3::
            sleep(0.1)
        end
    end

    local fetch_queue = { 1 }
    local available_chunk_space_count = math.max(math.ceil(AVAILABLE_MEMORY / arguments.chunk_size), 1)
    local num_old_chunks = math.floor((1 - NEW_CHUNKS_PERCENTAGE) * available_chunk_space_count)
    local num_new_chunks = math.max(math.floor(NEW_CHUNKS_PERCENTAGE * available_chunk_space_count), 1)
    local function fetch_chunks()
        if #fetch_queue == 0 then
            return
        end

        local chunk_to_fetch = table.remove(fetch_queue)

        if chunks[chunk_to_fetch] == nil then
            local chunk = fetch_stream(http_url_default, json.hash, chunk_to_fetch - 1)
            if not chunk then
                print("[ERROR] requested chunk not available")
            else
                chunks[chunk_to_fetch] = chunk
            end
        end

        for i = chunk_to_fetch - 1, chunk_to_fetch - num_old_chunks, -1 do
            if i <= 1 then break end

            if chunks[i] == nil then
                local chunk = fetch_stream(http_url_default, json.hash, i - 1)
                if chunk then
                    chunks[i] = chunk
                else
                    print("[ERROR] backward chunk " .. i .. " not available")
                end
            end
        end

        for i = chunk_to_fetch + 1, chunk_to_fetch + num_new_chunks do
            if i >= json.number_of_chunks then break end

            if chunks[i] == nil then
                local chunk = fetch_stream(http_url_default, json.hash, i - 1)
                if chunk then
                    chunks[i] = chunk
                else
                    print("[ERROR] forward chunk " .. i .. " not available")
                end
            end
        end

        local min_allowed = chunk_to_fetch - num_old_chunks
        local max_allowed = chunk_to_fetch + num_new_chunks

        for active_index, _ in pairs(chunks) do
            if active_index < min_allowed or active_index > max_allowed then
                chunks[active_index] = nil -- Speicher freigeben!
            end
        end
    end

    local function thread_fetch_chunks()
        while true do
            fetch_chunks()
            sleep(0.1)
        end
    end

    local function get_chunk(index)
        if chunks[index] == nil then
            table.insert(fetch_queue, index)
        end

        while chunks[index] == nil do
            sleep(0.05)
        end

        return chunks[index]
    end

    local function get_samples(index_global_samples_start, index_global_samples_end)
        local result = {}
        local chunk_size = arguments.chunk_size
        local number_of_chunks = json.number_of_chunks

        local first_chunk_index = math.floor(index_global_samples_start / chunk_size)
        local last_chunk_index = math.min(math.floor(index_global_samples_end / chunk_size), number_of_chunks - 1)

        local write_position = 1

        for chunk_index = first_chunk_index, last_chunk_index do
            local chunk = get_chunk(chunk_index + 1)

            if chunk and chunk.samples then
                local chunk_start_global = chunk_index * chunk_size

                local read_start = math.max(index_global_samples_start - chunk_start_global, 0) + 1
                local read_end = math.min(index_global_samples_end - chunk_start_global, chunk_size - 1) + 1

                local number_of_samples = read_end - read_start + 1

                if number_of_samples > 0 then
                    table.move(chunk.samples, read_start, read_end, write_position, result)
                    write_position = write_position + number_of_samples
                end
            end
        end

        return result
    end

    local function audio()
        if is_paused then
            return
        end

        time_audio = time_audio + time_delta

        --if #sampleBuffer <= 0 then
        --    is_running = not (download_index >= json.number_of_chunks - 1)
        --    return
        --end

        if should_update then
            index_samples_last = time_audio * SAMPLES_PER_SECOND
        end

        local index_samples_start = index_samples_last + 1
        local index_samples_end = math.min(index_samples_start + SPEAKER_BUFFER_SIZE - 1, json.number_of_samples)

        local function map(array, func)
            local result = {}
            for i, value in ipairs(array) do
                result[i] = func(value)
            end
            return result
        end

        local buffer = get_samples(index_samples_start, index_samples_end)
        local mapped = map(buffer, function(x) return math.max(math.min(x * volume, 127), -128) end)

        local success = speaker.playAudio(mapped)
        if not success then
            return
        end

        --os.pullEvent("speaker_audio_empty")

        index_samples_last = index_samples_end
        should_update = false
    end

    local function thread_audio()
        time_last = seconds()
        while is_running do
            local time_current = seconds()
            time_delta = time_current - time_last
            time_last = time_current

            audio()
            sleep(0.05)
        end
    end

    parallel.waitForAny(thread_audio, thread_fetch_chunks, input)
end

local function get_command()
    if arguments.list then
        return command_list
    elseif arguments.play then
        return command_play
    end
end

local function execute()
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