local Api = {}

local function get_parameter_string(parameters)
    local segments = {}
    for key, value in pairs(parameters) do
        local segment =  string.format("%s=%s", key, value)
        table.insert(segments, segment)
    end

    return table.concat(segments, "&")
end

local function get_url_string(address, endpoint, parameters)
    local result = string.format("http://%s/api%s", address, endpoint)

    local parameter_string = get_parameter_string(parameters)
    if #parameter_string > 0 then
        result = result .. "?" .. parameter_string
    end

    return result
end

-- @field address       ip:port
-- @field endpoint      /users/memphis_pc
-- @field parameters?   {filter = "a==b"}, default {}
-- @field method?       "POST/GET/...", default "GET"
local function fetch(address, endpoint, parameters, method)
    method = method or "GET"
    parameters = parameters or {}

    local request = {
        url = get_url_string(address, endpoint, parameters),
        timeout = CONSTANTS.HTTP_TIMEOUT,
        method = method
    }

    local response, message = http.get(request)
    if not response then
        term.setTextColor(colors.red)
        print(request.url .. ": " .. message)
        term.setTextColor(colors.white)

        return nil
    end

    local response_string, _ = response.readAll()
    return response_string
end

function Api.get_list(address)
    local json_string = fetch(address, "/media")
    return textutils.unserializeJSON(json_string)
end

function Api.get_media(address, index)
    local endpoint = string.format("/media/%d", index)
    local json_string = fetch(address, endpoint)
    return textutils.unserializeJSON(json_string)
end

function Api.get_chunk(address, index_media, index_chunk, samples_per_chunk)
    local parameters = {
        samples_per_chunk = samples_per_chunk
    }

    local endpoint = string.format("/media/%d/chunk/%d", index_media, index_chunk)
    local json_string = fetch(address, endpoint, parameters)
    return textutils.unserializeJSON(json_string)
end

function Api.get_cover(address, index)
    local parameters = {
        width = 96,
        height = 64
    }

    local endpoint = string.format("/media/%d/cover", index)
    return fetch(address, endpoint, parameters)
end

function Api.reload(address)
    return fetch(address, "/media/reload", {}, "POST")
end

return Api