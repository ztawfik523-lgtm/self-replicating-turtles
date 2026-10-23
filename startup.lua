-- Turtle Genesis bootstrap. Never assumes that a reboot means a safe move.
local ok, err = shell.run('/tg/main.lua', 'boot')
if not ok then printError('Genesis boot failed: ' .. tostring(err)) end
