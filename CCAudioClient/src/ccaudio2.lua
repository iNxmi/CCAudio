local VERSION = "1.0.0-alpha"

local MAXIMUM_MEMORY_USAGE = 0.90
local AVAILABLE_MEMORY = 1000000 * MAXIMUM_MEMORY_USAGE

local SKIP_AMOUNT = 1
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
                    print("paused")
                else
                    should_update = true
                    print("unpaused")
                end
            elseif key == keys.right then
                time_audio = time_audio + SKIP_AMOUNT
                speaker.stop()
                should_update = true
            elseif key == keys.left then
                time_audio = time_audio - SKIP_AMOUNT
                speaker.stop()
                should_update = true
            end
            ::continue3::
            sleep(0.1)
        end
    end

    local function checksum(list)
        local sum = 0
        for _, value in ipairs(list) do
            sum = sum + value
        end
        return sum
    end

    local chunk_to_fetch = 0
    local function fetch_chunks()
        local available_chunk_space_count = math.max(math.ceil(AVAILABLE_MEMORY / arguments.chunk_size), 1)
        local num_old_chunks = math.floor((1 - NEW_CHUNKS_PERCENTAGE) * available_chunk_space_count)
        local num_new_chunks = math.max(math.floor(NEW_CHUNKS_PERCENTAGE * available_chunk_space_count), 1)

        while true do
            -- fetch the requested chunk first, then the next 1, then the one before then all the ones after
            -- if request is chunk 5:  fetch in this order: 5, 6, 4, 7

            -- handle requested chunk
            if chunks[chunk_to_fetch] == nil then
                local chunk = fetch_stream(http_url_default, json.hash, chunk_to_fetch - 1)
                --print("fetchi chunkos " .. chunk_to_fetch)
                if not chunk then
                    print("[ERROR] requested chunk not available")
                else
                    chunks[chunk_to_fetch] = chunk
                end
            end

            -- handle chunks before request
            for i = chunk_to_fetch - 1, num_old_chunks, -1 do
                if i <= 1 then
                    break
                end
                --print("fetchi chunkos " .. i)
                if chunks[i] ~= nil then
                    --print("chokus already there")
                    goto continue2
                end
                -- fetch the chunks
                local chunk = fetch_stream(http_url_default, json.hash, i - 1)
                if not chunk then
                    print("[ERROR] requested chunk not available")
                else
                    chunks[i] = chunk
                end
                ::continue2::
            end

            -- handle chunks after request
            for i = chunk_to_fetch + 1, num_new_chunks, 1 do
                if i >= json.number_of_chunks then
                    break
                end
                --print("fetchi chunkos " .. i)
                if chunks[i] ~= nil then
                    --print("chunkos already there")
                    goto continue1
                end
                -- fetch the chunks
                local chunk = fetch_stream(http_url_default, json.hash, i - 1)
                if not chunk then
                    print("[ERROR] requested chunk not available")
                else
                    chunks[i] = chunk
                end
                ::continue1::
            end

            sleep(0.1)
        end
    end

    local function get_chunk(index)
        --print("I wanta have chunk: " .. index)
        if chunks[index] == nil then
            --print("chunkos not there, pls gimmi")
            chunk_to_fetch = index
        end
        while chunks[index] == nil do
            sleep(0.05) -- wait till fetch() fetched the requested chunk
        end
        --print("Yipiiii, got chunk: " .. index)
        return chunks[index]
    end

    local function get_samples(index_global_samples_start, index_global_samples_end)
        local timer_start = seconds()
        local samples = {}
        local index_chunk_start = 1 + math.floor(index_global_samples_start / arguments.chunk_size)
        local index_chunk_end = math.min(2 + math.ceil(index_global_samples_end / arguments.chunk_size), json.number_of_chunks)

        local iteration = 1
        for index_chunk = index_chunk_start, index_chunk_end do
            local chunk = get_chunk(index_chunk)
            table.move(chunk.samples, 1, #(chunk.samples), ((iteration - 1) * chunk.size) + 1, samples)
            iteration = iteration + 1
        end

        local result = {}
        local index_global_samples_length = index_global_samples_end - index_global_samples_start
        local index_normalized_samples_start = index_global_samples_start % arguments.chunk_size
        local index_normalized_samples_end = index_normalized_samples_start + index_global_samples_length
        table.move(samples, index_normalized_samples_start, index_normalized_samples_end, 1, result)

        -- print("time: " .. (seconds() - timer_start) * 1000)

        return result
    end

    local function audio()
        if is_paused then
            return
        end

        time_audio = time_audio + time_delta
        print((time_audio * SAMPLES_PER_SECOND) / arguments.chunk_size)
        --print(time_audio)

        --if #sampleBuffer <= 0 then
        --    is_running = not (download_index >= json.number_of_chunks - 1)
        --    return
        --end

        if should_update then
            index_samples_last = time_audio * SAMPLES_PER_SECOND
        end

        local index_samples_start = index_samples_last + 1
        local index_samples_end = index_samples_start + SPEAKER_BUFFER_SIZE - 1
        local buffer = get_samples(index_samples_start, index_samples_end)

        local success = speaker.playAudio(buffer)
        if not success then
            return
        end

        index_samples_last = index_samples_end
        should_update = false
    end

    time_last = seconds()

    local function main_loop()
        while is_running do
            local time_current = seconds()
            time_delta = time_current - time_last
            time_last = time_current

            audio()
            sleep(0.05)
        end
    end

    parallel.waitForAny(main_loop, fetch_chunks, input)
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