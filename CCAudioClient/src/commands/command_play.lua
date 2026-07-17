local instance = {}

function instance.register(argparse)
    local command = argparse:command("play", "Play music.")
    command:argument("file", "File to play.")
    command:option("-c --chunk_size", "Chunk size (in bytes)", 128 * 1024)
end

function instance.execute()

end

return instance