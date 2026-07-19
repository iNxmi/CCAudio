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

    local json_string, _ = response.readAll()
    return textutils.unserializeJSON(json_string)
end

function Api.refresh(address)
    return fetch (address, "/refresh", {}, "POST")
end

function Api.get_list(address)
    return fetch(address, "/list")
end

function Api.get_request(address, index, samples_per_chunk)
    local parameters = {
        index = index,
        samples_per_chunk = samples_per_chunk
    }

    return fetch(address, "/request", parameters, "POST")
end

function Api.get_chunk(address, hash, index)
    local parameters = {
        hash = hash,
        index = index
    }

    return fetch(address, "/chunk", parameters)
end

return Api