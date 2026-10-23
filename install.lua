-- Turtle Genesis remote installer.
-- Run: wget run https://raw.githubusercontent.com/ztawfik523-lgtm/self-replicating-turtles/main/install.lua
local BASE = 'https://raw.githubusercontent.com/ztawfik523-lgtm/self-replicating-turtles/main/'
local FILES = {
  'tg/config.lua', 'tg/state.lua', 'tg/log.lua', 'tg/fuel.lua',
  'tg/nav.lua', 'tg/survey.lua', 'tg/clone.lua', 'tg/replicate.lua',
  'tg/probe.lua', 'tg/main.lua', 'startup.lua',
}
local STAGE = '/tg-download'

assert(turtle, 'Run this installer inside a turtle')
assert(http and http.get, 'HTTP is disabled in CC: Tweaked')
assert(not fs.exists(STAGE), 'Remove previous /tg-download directory before trying again')
fs.makeDir(STAGE)

-- Fetch everything first, before changing installed programs.
for i, path in ipairs(FILES) do
  print(('Downloading %d/%d: %s'):format(i, #FILES, path))
  local response, err = http.get(BASE .. path)
  if not response then
    fs.delete(STAGE)
    error('Download failed for ' .. path .. ': ' .. tostring(err), 0)
  end
  local content = response.readAll()
  response.close()
  local dest = fs.combine(STAGE, path)
  local folder = fs.getDir(dest)
  if not fs.exists(folder) then fs.makeDir(folder) end
  local out = assert(fs.open(dest, 'w'))
  out.write(content)
  out.close()
  assert(fs.getSize(dest) > 0, 'Empty file: ' .. path)
end

-- Preserve existing state and back up any pre-existing startup script.
if fs.exists('/startup.lua') and not fs.exists('/startup.lua.genesis-backup') then
  fs.copy('/startup.lua', '/startup.lua.genesis-backup')
  print('Preserved old startup.lua in startup.lua.genesis-backup')
end
for _, path in ipairs(FILES) do
  local source = fs.combine(STAGE, path)
  local dest = '/' .. path
  local folder = fs.getDir(dest)
  if not fs.exists(folder) then fs.makeDir(folder) end
  if fs.exists(dest) then fs.delete(dest) end
  fs.move(source, dest)
end
fs.delete(STAGE)
print('Turtle Genesis installed! Run: reboot')
print('Then: tg/main.lua probe')
