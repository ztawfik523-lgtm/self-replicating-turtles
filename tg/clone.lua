-- Software inheritance using a child turtle ITEM inside an adjacent disk drive.
-- Only copies source code; never copies parent's position, log, or state.
local M = {}
local state = require('state')
local files = {
  'startup.lua',
  'tg/config.lua', 'tg/state.lua', 'tg/log.lua', 'tg/fuel.lua',
  'tg/nav.lua', 'tg/survey.lua', 'tg/clone.lua', 'tg/replicate.lua',
  'tg/main.lua', 'tg/probe.lua', 'tg/miner.lua', 'tg/factory.lua', 'tg/process.lua', 'tg/station.lua',
}
local function contents(path)
  local f = fs.open(path, 'r')
  assert(f, 'Cannot read ' .. path)
  local s = f.readAll()
  f.close()
  return s
end
function M.install(side)
  side = side or 'front'
  assert(peripheral.getType(side) == 'drive', 'Expected adjacent disk drive at ' .. side)
  assert(disk.isPresent(side), 'Insert turtle ITEM into drive')
  local mount = disk.getMountPath(side)
  assert(mount, 'Turtle item is not mounted; it may need initial placement/initialization')
  assert(not fs.isReadOnly(mount), 'Disk mount is read-only')
  assert(mount ~= '' and mount ~= '/', 'Refusing invalid mount')
  -- A reused turtle's old state would override the new lineage seed.
  for _, old in ipairs({'tg/state.dat', 'tg/state.bak', 'tg/state.tmp'}) do
    assert(not fs.exists(fs.combine(mount, old)),
      'Child contains an existing Genesis state; use a fresh initialized turtle item')
  end
  for _, relative in ipairs(files) do
    local source = '/' .. relative
    local target = fs.combine(mount, relative)
    assert(fs.exists(source), 'Missing source file ' .. source)
    local folder = fs.getDir(target)
    if not fs.exists(folder) then fs.makeDir(folder) end
    if fs.exists(target) then fs.delete(target) end
    fs.copy(source, target)
    assert(contents(source) == contents(target), 'Install verification failed: ' .. relative)
  end
  -- Controller-enabled parents pass their worker and controller address on to
  -- the offspring, so a booted child joins the same colony automatically.
  -- Legacy clones without a controller configuration retain legacy startup.
  if fs.exists('/tg/worker-config.dat') then
    for _,rel in ipairs({'tg/worker.lua','tg/workshop.lua','tg/bootstrap.lua','tg/worker-entry.lua'}) do
      local src='/'..rel
      assert(fs.exists(src),'Controller clone missing '..src)
      local dst=fs.combine(mount,rel)
      if not fs.exists(fs.getDir(dst)) then fs.makeDir(fs.getDir(dst)) end
      if fs.exists(dst) then fs.delete(dst) end
      fs.copy(src,dst)
      assert(contents(src)==contents(dst),'Worker inheritance copy failed: '..rel)
    end
    local dest=fs.combine(mount,'tg/worker-config.dat')
    if fs.exists(dest) then fs.delete(dest) end
    fs.copy('/tg/worker-config.dat',dest)
    assert(contents('/tg/worker-config.dat')==contents(dest),
      'Inherited controller address did not match')
  end
  -- Record lineage without cloning any previous robot's state.
  local seedPath = fs.combine(mount, 'tg/seed.dat')
  local seed = {schema = 1, generation = state.data.generation + 1,
    parentID = os.getComputerID(), auto = state.data.autonomyEnabled == true}
  if fs.exists(seedPath) then fs.delete(seedPath) end
  local f = assert(fs.open(seedPath, 'w'))
  f.write(textutils.serialize(seed))
  f.close()
  return mount
end
return M
