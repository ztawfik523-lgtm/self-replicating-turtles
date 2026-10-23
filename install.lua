-- Turtle Genesis installer. Pin downloads to a fixed commit; no api.github.com dependency.
-- Run inside a turtle with: wget run <URL to this file>
local REPO = 'ztawfik523-lgtm/self-replicating-turtles'
local sha = '6e0aa8ff284ed9847337785002079c7ebe638a65'
local STAGE = '/tg-download'
local EXPECTED = '0.3.5'
local FILES = {
  'tg/config.lua', 'tg/state.lua', 'tg/log.lua', 'tg/fuel.lua',
  'tg/nav.lua', 'tg/survey.lua', 'tg/clone.lua', 'tg/replicate.lua',
  'tg/probe.lua', 'tg/main.lua', 'tg/miner.lua', 'tg/factory.lua', 'tg/process.lua', 'tg/station.lua', 'startup.lua',
}

assert(turtle, 'This installer must run inside a turtle')
assert(http and http.get, 'HTTP is disabled in CC: Tweaked')
if fs.exists(STAGE) then fs.delete(STAGE) end

-- raw.githubusercontent.com works in CC: Tweaked where api.github.com may be blocked.
-- This revision contains syntax-checked v0.3.4 runtime files.
local base = 'https://raw.githubusercontent.com/' .. REPO .. '/' .. sha .. '/'
print('Installing Turtle Genesis from commit ' .. sha:sub(1, 12))

fs.makeDir(STAGE)
for i, path in ipairs(FILES) do
  print(('Downloading %d/%d: %s'):format(i, #FILES, path))
  local res, err = http.get(base .. path)
  if not res then
    fs.delete(STAGE)
    error('Download failed for ' .. path .. ': ' .. tostring(err), 0)
  end
  local source = res.readAll()
  res.close()
  assert(#source > 0, 'Empty source: ' .. path)
  local func, compileErr = load(source, '@' .. path)
  assert(func, 'Invalid Lua in ' .. path .. ': ' .. tostring(compileErr))
  local dest = fs.combine(STAGE, path)
  local folder = fs.getDir(dest)
  if folder ~= '' and not fs.exists(folder) then fs.makeDir(folder) end
  local out = assert(fs.open(dest, 'w'), 'Cannot create ' .. dest)
  out.write(source)
  out.close()
end

-- Refuse to overwrite working files if the fetched commit is not the expected build.
local handle = assert(fs.open(fs.combine(STAGE, 'tg/config.lua'), 'r'))
local versionFile = handle.readAll()
handle.close()
assert(versionFile:find("version = '" .. EXPECTED .. "'", 1, true),
  'Wrong version in download; installed files unchanged')
local mainFile = assert(fs.open(fs.combine(STAGE, 'tg/main.lua'), 'r'))
local mainContents = mainFile.readAll()
mainFile.close()
assert(mainContents:find("command == 'recover'", 1, true),
  'Missing recovery command; installed files unchanged')

if fs.exists('/startup.lua') and not fs.exists('/startup.lua.genesis-backup') then
  fs.copy('/startup.lua', '/startup.lua.genesis-backup')
end

for _, path in ipairs(FILES) do
  local from, to = fs.combine(STAGE, path), '/' .. path
  local folder = fs.getDir(to)
  if folder ~= '' and not fs.exists(folder) then fs.makeDir(folder) end
  if fs.exists(to) then fs.delete(to) end
  fs.move(from, to)
end
fs.delete(STAGE)

print('Installed Turtle Genesis ' .. EXPECTED .. ' (' .. sha:sub(1, 12) .. ')')
print('State preserved. New commands are ready; no reboot required.')
