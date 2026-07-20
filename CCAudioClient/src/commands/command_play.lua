local Api = require("api")
local gfx = require("graphics")

local CommandPlay = {}

CommandPlay.NAME = "play"

function CommandPlay.register(parser)
    local command = parser:command(CommandPlay.NAME, "Play music.")
    command:argument("file", "File to play.")
    command:option("-c --chunk_size", "Chunk size (in bytes)", 128 * 1024)
    return command
end


local function seconds()
    return os.epoch("utc") / 1000
end

local function benchmark(func, ...)
    local start_time = os.epoch("utc")
    local ret = table.pack(func(...))
    local end_time = os.epoch("utc") - start_time
    gfx.set_text_color(colors.red)
    gfx.print(end_time .. "ms")
    gfx.set_text_color(colors.white)
    return table.unpack(ret, 1 ,ret.n)
end

local function benchmark_target(func, target, ...)
    target = target or term.current()
    local start_time = os.epoch("utc")
    local ret = table.pack(func(...))
    local end_time = os.epoch("utc") - start_time
    local old_target = term.redirect(target)
    term.setTextColor(colors.red)
    print(end_time .. "ms")
    term.setTextColor(colors.white)
    term.redirect(old_target)
    return table.unpack(ret, 1 ,ret.n)
end

function CommandPlay.execute(arguments)

    local speaker = peripheral.find("speaker")
    if not speaker then
        error("No speaker found.")
        return
    end

    local json = Api.get_request(arguments.address, arguments.file, arguments.chunk_size)
    if json == nil then return end

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
                term.clear()
                term.setCursorPos(1, 1)
            elseif key == keys.p or key == keys.space then
                is_paused = not is_paused
                if is_paused then
                    speaker.stop()
                else
                    should_update = true
                end
            elseif key == keys.right then
                time_audio = math.min(math.max(time_audio + CONSTANTS.SKIP_AMOUNT, 0),  json.number_of_samples / CONSTANTS.SPEAKER_SAMPLES_PER_SECOND)
                speaker.stop()
                should_update = true
            elseif key == keys.left then
                time_audio = math.min(math.max(time_audio - CONSTANTS.SKIP_AMOUNT, 0),  json.number_of_samples / CONSTANTS.SPEAKER_SAMPLES_PER_SECOND)
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
            local chunk = Api.get_chunk(arguments.address, json.hash, chunk_to_fetch - 1)

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

            local chunk = Api.get_chunk(arguments.address, json.hash, i - 1)
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

            local chunk = Api.get_chunk(arguments.address, json.hash, i - 1)
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


        local function map(array, func)
            local res = {}
            for i, value in ipairs(array) do
                res[i] = func(value)
            end
            return res
        end

        local mapped = map(result, function(sample)
            local function clip(value, min, max)
                return math.max(math.min(max, value),min)
            end

            local multiplier = math.pow(10, volume_in_decibels / 20)
            return clip(sample * multiplier, -128, 127)
        end)


        return mapped
    end

    local image = nil
    if json.music.cover ~= nil then
        image = paintutils.parseImage(json.music.cover)
    end

    --local monitor = peripheral.find("monitor")
    --if not monitor then
    --    monitor = term.current()
    --end

    local function render()
        local width, height = gfx.get_dimensions()
        gfx.clear(colors.black)

        if image ~= nil then
            gfx.draw_sprite((width/ 2) - 48 + 1, 4 + ((height - 4 - 4) / 2) - 32, image)
        end

        local name = arguments.file .. ". " .. json.music.name
        gfx.draw_text_centered((width / 2), 2, name)

        local volume_text = "Volume: " .. volume_in_decibels .. "db "
        local status_text = " Status: "
        if is_paused then
            status_text = status_text .. "Paused"
        else
            status_text = status_text .. "Playing"
        end
        local finished_string = status_text .. string.rep(" ", width - #volume_text - #status_text) .. volume_text

        gfx.draw_text(1, height - 1, finished_string)

        local duration_current = os.date("!%H:%M:%S", time_audio)
        local duration_total = os.date("!%H:%M:%S", json.number_of_samples / CONSTANTS.SPEAKER_SAMPLES_PER_SECOND)

        local progress_percentage = time_audio / (json.number_of_samples / CONSTANTS.SPEAKER_SAMPLES_PER_SECOND)
        local progress_length = width - #duration_current - #duration_total - 6

        local progress_current_string = string.rep("=", math.ceil(progress_length * progress_percentage))
        if #progress_current_string >= 1 then
            progress_current_string = string.sub(progress_current_string, 1, #progress_current_string - 1) .. ">"
        end
        local progress_pending_string = string.rep("-", math.floor(progress_length * (1 - progress_percentage)))
        local progress_string = progress_current_string .. progress_pending_string

        local result = string.format(" %s |%s| %s ", duration_current, progress_string, duration_total)
        gfx.draw_text(1, height - 3, result)

        gfx.render()
    end

    local function thread_render()
        while is_running do
            render()
            sleep(0.05)
        end
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
            index_samples_last = time_audio * CONSTANTS.SPEAKER_SAMPLES_PER_SECOND
        end

        local index_samples_start = index_samples_last + 1
        local index_samples_end = math.min(index_samples_start + CONSTANTS.SPEAKER_BUFFER_SIZE - 1, json.number_of_samples)

        local buffer = get_samples(index_samples_start, index_samples_end)
        if #buffer <= 0 then
            is_running = false
            return
        end

        local success = speaker.playAudio(buffer)
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

    gfx.set_target(term.native())
    gfx.set_mode(1)
    parallel.waitForAny(thread_audio, thread_fetch_chunks, input, thread_render)
end

return CommandPlay