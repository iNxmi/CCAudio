local Constants = {
    VERSION = "1.0.0-alpha",
    MAXIMUM_MEMORY_USAGE = 0.90,
    SKIP_AMOUNT = 25,
    NEW_CHUNKS_PERCENTAGE = 0.7,
    SPEAKER_BUFFER_SIZE = 64 * 1024,
    SAMPLES_PER_SECOND = 48000,
    HTTP_TIMEOUT = 3.0
}

Constants.AVAILABLE_MEMORY = 1000000 * Constants.MAXIMUM_MEMORY_USAGE

local proxy = {}
local proxy_mt = {
    __index = Constants,
    __newindex = function()
        error("Attempt to modify read-only constant.", 2)
    end
}
setmetatable(proxy, proxy_mt)

return proxy