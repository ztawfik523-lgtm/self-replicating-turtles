local M = {}
local config = require('config')
local PATH = '/tg/events.log'
function M.event(kind, details)
  local line = ('%s id=%s %s %s\n'):format(tostring(os.epoch('utc')), tostring(os.getComputerID()), tostring(kind), tostring(details or ''))
  if fs.exists(PATH) and fs.getSize(PATH) > config.logLimitBytes then
    if fs.exists('/tg/events.old') then fs.delete('/tg/events.old') end
    fs.move(PATH, '/tg/events.old')
  end
  local f = fs.open(PATH, 'a')
  if f then f.write(line); f.close() end
end
return M
