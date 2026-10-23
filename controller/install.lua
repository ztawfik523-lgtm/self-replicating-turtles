-- Turtle Genesis controller-development installer.
-- This is NOT the v0.3.5 stable installer. The user must explicitly select it.
-- After a full first-birth in-game acceptance run this can become the default.
local argv={...}
local url=argv[1]
assert(type(url)=='string' and
  (url:sub(1,5)=='ws://' or url:sub(1,6)=='wss://'),
  'Pass controller address: ws://HOST:8765')
assert(not url:find('%s'),'Controller URL cannot contain whitespace')
assert(turtle and http and http.get,'Run inside a CC: Tweaked turtle with HTTP enabled')

local REPO='ztawfik523-lgtm/self-replicating-turtles'
-- PINNED_REV is advanced only after automated integration tests pass.
local PINNED_REV='6ab440c614477784b257099036346cd7fc61c8dc'
local VERSION='0.4.0-dev'
local STAGE='/tg-controller-download'
local BACKUP='/tg-controller-backup'
local paths={
 'startup.lua','tg/config.lua','tg/state.lua','tg/log.lua','tg/fuel.lua',
 'tg/nav.lua','tg/survey.lua','tg/clone.lua','tg/replicate.lua',
 'tg/probe.lua','tg/main.lua','tg/miner.lua','tg/factory.lua',
 'tg/process.lua','tg/station.lua','tg/worker.lua','tg/workshop.lua',
 'tg/worker-entry.lua',
}

local function folder(path)
 local parent=fs.getDir(path)
 if parent~='' and not fs.exists(parent) then fs.makeDir(parent) end
end
local function read(path)
 local f=assert(fs.open(path,'r'),'Unable to read '..path)
 local s=f.readAll();f.close();return s
end
local function write(path,data)
 folder(path)
 local f=assert(fs.open(path,'w'),'Unable to write '..path)
 f.write(data);f.close()
end
local function cleanup()
 if fs.exists(STAGE) then fs.delete(STAGE) end
 if fs.exists(BACKUP) then fs.delete(BACKUP) end
end
assert(not fs.exists(STAGE) and not fs.exists(BACKUP),
 'Previous staging files exist; inspect before another install')
fs.makeDir(STAGE)
local base='https://raw.githubusercontent.com/'..REPO..'/'..PINNED_REV..'/'
local ok,err=pcall(function()
 for i,path in ipairs(paths) do
  print(('Staging %d/%d %s'):format(i,#paths,path))
  local response,why=http.get(base..path)
  assert(response,'Could not fetch '..path..': '..tostring(why))
  local source=response.readAll();response.close()
  assert(#source>0,'Empty source for '..path)
  local executable,compileError=load(source,'@'..path)
  assert(executable,'Lua syntax error in '..path..': '..tostring(compileError))
  write(fs.combine(STAGE,path),source)
 end
 local config=read(fs.combine(STAGE,'tg/config.lua'))
 assert(config:find("version = '"..VERSION.."'",1,true),
  'Fetched an unexpected Genesis version')
 local child=read(fs.combine(STAGE,'tg/clone.lua'))
 for _,name in ipairs({'tg/worker.lua','tg/workshop.lua',
                       'tg/worker-entry.lua'}) do
  assert(child:find(name,1,true),'Child cloning manifest missing '..name)
 end
end)
if not ok then
 fs.delete(STAGE)
 error('No live files changed: '..tostring(err),0)
end

-- Copy the original files before replacing them. Preserved states,
-- logs and per-turtle job journals are never part of the downloaded set.
fs.makeDir(BACKUP)
local existing={}
for _,path in ipairs(paths) do
 if fs.exists('/'..path) then
  existing[path]=true
  local dest=fs.combine(BACKUP,path)
  folder(dest)
  fs.copy('/'..path,dest)
 end
end
local oldConfig=fs.exists('/tg/worker-config.dat')
if oldConfig then fs.copy('/tg/worker-config.dat',
                           fs.combine(BACKUP,'tg/worker-config.dat')) end
local replaced={}
local installed,installErr=pcall(function()
 for _,path in ipairs(paths) do
  local source=fs.combine(STAGE,path)
  local target='/'..path
  folder(target)
  -- Record BEFORE deleting the old file, so a failed copy also rolls back.
  replaced[#replaced+1]=path
  if fs.exists(target) then fs.delete(target) end
  fs.copy(source,target)
 end
 write('/tg/worker-config.dat',url)
end)
if not installed then
 for _,path in ipairs(replaced) do
  local target='/'..path
  if fs.exists(target) then fs.delete(target) end
  if existing[path] then fs.copy(fs.combine(BACKUP,path),target) end
 end
 if fs.exists('/tg/worker-config.dat') then fs.delete('/tg/worker-config.dat') end
 if oldConfig then
  fs.copy(fs.combine(BACKUP,'tg/worker-config.dat'),'/tg/worker-config.dat')
 end
 cleanup()
 error('Install rolled back: '..tostring(installErr),0)
end
cleanup()
print('Genesis controller runtime installed; persistent state preserved')
print('Starting worker and connecting to '..url)
local success,why=shell.run('/tg/worker-entry.lua')
if not success then printError('Worker stopped: '..tostring(why)) end
