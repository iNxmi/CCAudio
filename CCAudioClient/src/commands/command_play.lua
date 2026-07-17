local api = require("api")
local constants = require("constants")

local CommandPlay = {}
local CommandPlay_mt = { __index = CommandPlay }

function CommandPlay.new()
    local self = {}
    setmetatable(self, CommandPlay_mt)
    return self
end

function CommandPlay:register(parser)
    local command = parser:command("play", "Play music.")
    command:argument("file", "File to play.")
    command:option("-c --chunk_size", "Chunk size (in bytes)", 128 * 1024)
end

function CommandPlay:execute(arguments)

    local function seconds()
        return os.epoch("utc") / 1000
    end

    local speaker = peripheral.find("speaker")
    if not speaker then
        error("No speaker found.")
        return
    end

    local json = api.fetch_request("http://" .. arguments.address .. ":" .. arguments.port, arguments.file, arguments.chunk_size)

    local is_running = true
    local is_paused = false
    local should_update = false

    local time_last = 0
    local time_delta = 0
    local time_audio = 0

    local volume_in_decibels = 0

    local index_samples_last = 0

    local chunks = {}

    local function input()
        while true do
            local event = { os.pullEvent("key") }
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
                else
                    should_update = true
                end
            elseif key == keys.right then
                time_audio = math.min(math.max(time_audio + CONSTANTS.SKIP_AMOUNT, 0),  json.number_of_samples / CONSTANTS.SAMPLES_PER_SECOND)
                speaker.stop()
                should_update = true
            elseif key == keys.left then
                time_audio = math.min(math.max(time_audio - CONSTANTS.SKIP_AMOUNT, 0),  json.number_of_samples / CONSTANTS.SAMPLES_PER_SECOND)
                speaker.stop()
                should_update = true
            elseif key == keys.up then
                volume_in_decibels = volume_in_decibels + 1
                speaker.stop()
                should_update = true
            elseif key == keys.down then
                volume_in_decibels = volume_in_decibels - 1
                speaker.stop()
                should_update = true
            end
            :: continue3 ::
            sleep(0.1)
        end
    end

    local fetch_queue = { 1 }
    local available_chunk_space_count = math.max(math.ceil(CONSTANTS.AVAILABLE_MEMORY / arguments.chunk_size), 1)
    local num_old_chunks = math.floor((1 - CONSTANTS.NEW_CHUNKS_PERCENTAGE) * available_chunk_space_count)
    local num_new_chunks = math.max(math.floor(CONSTANTS.NEW_CHUNKS_PERCENTAGE * available_chunk_space_count), 1)
    local function fetch_chunks()
        if #fetch_queue == 0 then
            return
        end

        local chunk_to_fetch = table.remove(fetch_queue)

        if chunks[chunk_to_fetch] == nil then
            local chunk = api.fetch_stream("http://" .. arguments.address .. ":" .. arguments.port, json.hash, chunk_to_fetch - 1)

            if not chunk then
                print("[ERROR] requested chunk not available")
            else
                chunks[chunk_to_fetch] = chunk
            end
        end

        for i = chunk_to_fetch - 1, num_old_chunks, -1 do
            if i <= 1 then
                break
            end

            if chunks[i] ~= nil then
                goto continue2
            end

            local chunk = api.fetch_stream("http://" .. arguments.address .. ":" .. arguments.port, json.hash, i - 1)
            if not chunk then
                print("[ERROR] requested chunk not available")
            else
                chunks[i] = chunk
            end

            :: continue2 ::
        end

        for i = chunk_to_fetch + 1, num_new_chunks, 1 do
            if i >= json.number_of_chunks then
                break
            end

            if chunks[i] ~= nil then
                goto continue1
            end

            local chunk = api.fetch_stream("http://" .. arguments.address .. ":" .. arguments.port, json.hash, i - 1)
            if not chunk then
                print("[ERROR] requested chunk not available")
            else
                chunks[i] = chunk
            end

            :: continue1 ::
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

    local function render()
        local position_x, position_y = term.getCursorPos()
        local width, height = term.getSize()

        term.clearLine()
        term.setCursorPos(1, position_y)

        local duration_current = os.date("!%H:%M:%S", time_audio)
        local duration_total = os.date("!%H:%M:%S", json.number_of_samples / CONSTANTS.SAMPLES_PER_SECOND)

        local progress_percentage = time_audio / (json.number_of_samples / CONSTANTS.SAMPLES_PER_SECOND)

        local progress = string.rep("-", (width - #duration_current - #duration_total - 6) * progress_percentage) .. string.rep(" ", (width - #duration_current - #duration_total - 6) * (1 - progress_percentage))
        local result = string.format(" %s |%s| %s ", duration_current, progress, duration_total)
        term.write(result)
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
            index_samples_last = time_audio * CONSTANTS.SAMPLES_PER_SECOND
        end

        local index_samples_start = index_samples_last + 1
        local index_samples_end = math.min(index_samples_start + CONSTANTS.SPEAKER_BUFFER_SIZE - 1, json.number_of_samples)

        local function map(array, func)
            local result = {}
            for i, value in ipairs(array) do
                result[i] = func(value)
            end
            return result
        end

        local buffer = get_samples(index_samples_start, index_samples_end)
        local mapped = map(buffer, function(x)
            return math.max(math.min(x * (math.pow(10, volume_in_decibels / 20)), 127), -128)
        end)

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
            render()
            sleep(0.05)
        end
    end

    parallel.waitForAny(thread_audio, thread_fetch_chunks, input)
end

return CommandPlay