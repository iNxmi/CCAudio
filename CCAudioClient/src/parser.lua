local argparse = require("libraries/argparse__0_7_2")

local Parser = {}

local Parser_mt = {
    __index = Parser
}

local commands = {}

function Parser.new()
    local self = setmetatable({}, Parser_mt)
    self.parser = argparse("script", "Example Description.")

    self.parser:flag("-d --debug", "print debug information")
    self.parser:flag("-v --version", "print version")

    self.parser:option("-a --address", "set server address (ip:port)", "127.0.0.1:8080")

    return self
end

function Parser:error(message)
    error(message, 0)
end

function Parser:help(...)
    local help = self.parser:help(...)
    error(help, 0)
end

function Parser:parse(raw_arguments)
    local arguments = self.parser:parse(raw_arguments)

    local command = nil
    for name, cmd in pairs(commands) do
        if arguments[name] == true then
            command = cmd
        end
    end

    return arguments, command
end

function Parser:register_command(command)
    commands[command.NAME] = command
    command.register(self.parser)
end

return Parser