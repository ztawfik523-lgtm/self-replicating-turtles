-- Turtle Genesis controller-development installer.
-- This is NOT the v0.3.5 stable installer. The user must explicitly select it.
-- After a full first-birth in-game acceptance run this can become the default.
local argv={...}
local url=argv[1]
local BOOTSTRAP=argv[2]=='bootstrap'
assert(not argv[2] or BOOTSTRAP,'Optional second argument must be bootstrap')
assert(type(url)=='string' and
  (url:sub(1,5)=='ws://' or url:sub(1,6)=='wss://'),
  'Pass controller address: ws://HOST:8765')
assert(not url:find('%s'),'Controller URL cannot contain whitespace')
assert(turtle and http and http.get,'Run inside a CC: Tweaked turtle with HTTP enabled')

local REPO='ztawfik523-lgtm/self-replicating-turtles'
-- PINNED_REV is advanced only after automated integration tests pass.
local PINNED_REV='1a2c7a6d6ec23decc99aab184d319d3b3189460f'
local VERSION='0.5.0-dev'
local STAGE='/tg-controller-download'
local BACKUP='/tg-controller-backup'
local paths={
 'startup.lua','tg/config.lua','tg/state.lua','tg/log.lua','tg/fuel.lua',
 'tg/nav.lua','tg/survey.lua','tg/clone.lua','tg/replicate.lua',
 'tg/probe.lua','tg/main.lua','tg/miner.lua','tg/factory.lua',
 'tg/process.lua','tg/station.lua','tg/worker.lua','tg/workshop.lua',
 'tg/bootstrap.lua','tg/worker-entry.lua',
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
-- If the game closed halfway through an earlier installation, restore the
-- last complete backup automatically before attempting the next update.
local function recoverPrevious()
 if fs.exists(BACKUP) then
  if fs.exists(fs.combine(BACKUP,'READY')) then
   print('Recovering previous interrupted controller installation')
   for _,path in ipairs(paths) do
    local target='/'..path
    local old=fs.combine(BACKUP,path)
    if fs.exists(target) then fs.delete(target) end
    if fs.exists(old) then
     folder(target)
     fs.copy(old,target)
    end
   end
   local current='/tg/worker-config.dat'
   local old=fs.combine(BACKUP,'tg/worker-config.dat')
   if fs.exists(current) then fs.delete(current) end
   if fs.exists(old) then fs.copy(old,current) end
   local bootstrap='/tg/bootstrap-opt-in.dat'
   local bootstrapOld=fs.combine(BACKUP,'tg/bootstrap-opt-in.dat')
   if fs.exists(bootstrap) then fs.delete(bootstrap) end
   if fs.exists(bootstrapOld) then fs.copy(bootstrapOld,bootstrap) end
  end
  fs.delete(BACKUP)
 end
 if fs.exists(STAGE) then fs.delete(STAGE) end
end
recoverPrevious()
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
                       'tg/bootstrap.lua','tg/worker-entry.lua'}) do
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
local oldBootstrap=fs.exists('/tg/bootstrap-opt-in.dat')
if oldBootstrap then fs.copy('/tg/bootstrap-opt-in.dat',
   fs.combine(BACKUP,'tg/bootstrap-opt-in.dat')) end
if oldConfig then fs.copy('/tg/worker-config.dat',
                           fs.combine(BACKUP,'tg/worker-config.dat')) end
-- The READY marker is committed only after every backup is complete.
write(fs.combine(BACKUP,'READY'),'backup complete')
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
 -- Explicit M2 opt-in. Installing this runtime on an existing reproducing
 -- colony must never send the parents on a new exploration mission.
 if BOOTSTRAP then write('/tg/bootstrap-opt-in.dat','enabled') end
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
 if fs.exists('/tg/bootstrap-opt-in.dat') then fs.delete('/tg/bootstrap-opt-in.dat') end
 if oldBootstrap then
  fs.copy(fs.combine(BACKUP,'tg/bootstrap-opt-in.dat'),'/tg/bootstrap-opt-in.dat')
 end
 cleanup()
 error('Install rolled back: '..tostring(installErr),0)
end
cleanup()
print('Genesis controller runtime installed; persistent state preserved')
print('Starting worker and connecting to '..url)
local success,why=shell.run('/tg/worker-entry.lua')
if not success then printError('Worker stopped: '..tostring(why)) end
