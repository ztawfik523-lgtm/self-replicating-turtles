-- Turtle Genesis crafting recovery patch.
-- Run ON THE TURTLE after Ctrl+T stops the old worker.
-- Does NOT touch /tg/state.dat, furnace ingredients, job journal or controller.
local REV='9b3d9736995863895398ba8ce26ee594a6c17100'
local BASE='https://raw.githubusercontent.com/ztawfik523-lgtm/self-replicating-turtles/'..REV..'/'
local NAMES={'tg/factory.lua','tg/workshop.lua','tg/worker.lua'}
local STAGE='/tg-crafting-repair-download'
local BACKUP='/tg-crafting-repair-backup'
assert(turtle and http and http.get,'Run this in the turtle, with HTTP enabled')
assert(fs.exists('/tg/worker-config.dat'),
  'No existing controller worker configuration; use experimental installer first')
assert(not fs.exists(STAGE) and not fs.exists(BACKUP),
  'Previous repair staging exists. Do not overwrite without examining it.')
local function folder(path)
 local parent=fs.getDir(path)
 if parent~='' and not fs.exists(parent) then fs.makeDir(parent) end
end
local function write(path,s)
 folder(path)
 local file=assert(fs.open(path,'w'),'Cannot write '..path)
 file.write(s);file.close()
end
local function fetch()
 fs.makeDir(STAGE)
 for i,name in ipairs(NAMES) do
  print(('Downloading repair %d/%d %s'):format(i,#NAMES,name))
  local response,reason=http.get(BASE..name)
  assert(response,'Download error for '..name..': '..tostring(reason))
  local body=response.readAll();response.close()
  assert(load(body,'@'..name),'Invalid source: '..name)
  write(fs.combine(STAGE,name),body)
 end
end
local ok,why=pcall(fetch)
if not ok then
 fs.delete(STAGE)
 error('Repair not applied: '..tostring(why),0)
end
fs.makeDir(BACKUP)
for _,name in ipairs(NAMES) do
 local target='/'..name
 assert(fs.exists(target),'Missing installed file '..target)
 local backup=fs.combine(BACKUP,name)
 folder(backup)
 fs.copy(target,backup)
end
local changed={}
local applied,reason=pcall(function()
 for _,name in ipairs(NAMES) do
  local target='/'..name
  changed[#changed+1]=name
  fs.delete(target)
  fs.copy(fs.combine(STAGE,name),target)
 end
end)
if not applied then
 for _,name in ipairs(changed) do
  local target='/'..name
  if fs.exists(target) then fs.delete(target) end
  fs.copy(fs.combine(BACKUP,name),target)
 end
 fs.delete(STAGE);fs.delete(BACKUP)
 error('Repair rolled back: '..tostring(reason),0)
end
fs.delete(STAGE);fs.delete(BACKUP)
print('Crafting repair installed; resources and active birth kept')
print('Restarting worker to resume the SAME birth task')
shell.run('/tg/worker-entry.lua')
