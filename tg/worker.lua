-- Turtle Genesis controller worker (experimental; not in pinned live installer).
local M={}
local state=require('state')
local journal='/tg/worker-job.dat'
local journalBackup=journal..'.bak'
local configFile='/tg/worker-config.dat'
local function configuredURL()
 if fs.exists(configFile) then
  local f=assert(fs.open(configFile,'r'))
  local url=f.readAll()
  f.close()
  return url
 end
 return settings.get('genesis.controller','ws://127.0.0.1:8765')
end
local function saveURL(url)
 assert(type(url)=='string' and (url:sub(1,5)=='ws://' or url:sub(1,6)=='wss://'),
  'Controller URL must use WebSocket')
 local f=assert(fs.open(configFile,'w'))
 f.write(url)
 f.close()
end
local function readJournal()
 for _,path in ipairs({journal,journalBackup}) do
  if fs.exists(path) then
   local f=fs.open(path,'r')
   if f then
    local ok,value=pcall(function()return textutils.unserialize(f.readAll())end)
    f.close()
    if ok and type(value)=='table' and type(value.id)=='string'
      and type(value.status)=='string' then return value end
   end
  end
 end
 return {}
end
local function writeJournal(v)
 local tmp=journal..'.tmp'
 local f=assert(fs.open(tmp,'w'))
 f.write(textutils.serialize(v));f.close()
 if fs.exists(journalBackup) then fs.delete(journalBackup) end
 if fs.exists(journal) then fs.move(journal,journalBackup) end
 fs.move(tmp,journal)
end
local function snapshot()
 local inv={}
 for i=1,16 do
  local d=turtle.getItemDetail(i)
  if d then inv[#inv+1]={slot=i,name=d.name,count=d.count} end
 end
 local front,fb=turtle.inspect()
 local below,bb=turtle.inspectDown()
 local d=state.data
 -- Storage unavailable is NOT the same as an observed empty chest.
 local storage=nil
 local storage_observed=false
 local chest=peripheral.wrap('bottom')
 if chest and type(chest.list)=='function' then
  storage={}
  storage_observed=true
  for _,item in pairs(chest.list()) do
   if type(item)=='table' and type(item.name)=='string' then
    storage[item.name]=(storage[item.name] or 0)+(item.count or 0)
   end
  end
 end
 return {inventory=inv,storage=storage,storage_observed=storage_observed,
  fuel=turtle.getFuelLevel(),
  pose=d.pose,generation=d.generation,
  front=front and fb.name or nil,bottom=below and bb.name or nil,
  processing=d.processing~=nil,manufacturing=d.manufacture~=nil,
  replication=d.replication~=nil,station=d.station~=nil,
  birth=d.birth~=nil,children=d.children or 0,
  bootstrap_enabled=fs.exists('/tg/bootstrap-opt-in.dat'),
  bootstrap_done=d.bootstrap and d.bootstrap.complete==true or false,
  bootstrap_stage=d.bootstrap and d.bootstrap.stage or nil}
end
local function execute(job)
 local a=job.action
 if a=='observe' then return snapshot() end
 if a=='process' then
  local kind=job.args and job.args.kind
  assert(kind=='iron' or kind=='gold' or kind=='stone'
      or kind=='glass' or kind=='charcoal','Invalid smelting job')
  local n=require('process').run(kind)
  return {processed=n,snapshot=snapshot()}
 end
 if a=='collect' then require('factory').collect();return snapshot() end
 if a=='station_pack' then require('station').pack();return snapshot() end
 if a=='bootstrap' then
  require('bootstrap').run(job.id)
  return {base_established=true,snapshot=snapshot()}
 end
 if a=='birth' then
  require('workshop').run(job.id)
  return {child_created=true,snapshot=snapshot()}
 end
 if a=='produce' then
  assert(peripheral.hasType('front','drive') and not disk.isPresent('front'),
    'Need empty disk drive in front')
  assert(require('factory').make(),'Manufacture did not finish')
  require('replicate').lab()
  return {child_created=true,snapshot=snapshot()}
 end
 error('Unknown command: '..tostring(a))
end
function M.handle(job)
 assert(type(job)=='table' and type(job.id)=='string'
    and type(job.action)=='string','Invalid job')
 local previous=readJournal()
 if previous.id==job.id then
  -- A failed birth is not complete: equipment/material corrections should
  -- retry the original ID, not manufacture a second child under a new ID.
  if previous.status=='done' then
   if (job.action~='birth' and job.action~='bootstrap') or
      (previous.result and previous.result.ok) then
    return previous.result
   end
   if job.action=='birth' and not state.data.birth then
    return previous.result
   end
   if job.action=='bootstrap' and not state.data.bootstrap then
    return previous.result
   end
   print('Retrying paused '..job.action..' '..job.id)
  end
  -- Birth is designed to resume from observed resources and lineage count.
  -- Never retry an arbitrary legacy manufacturing operation blindly.
  if previous.status=='started' and job.action~='birth'
      and job.action~='bootstrap' then
   return {type='result',id=job.id,ok=false,
      error='Interrupted operation requires physical reconciliation'}
  end
 end
 if previous.status=='started' and previous.id~=job.id then
  return {type='result',id=job.id,ok=false,
    error='Another job is interrupted'}
 end
 writeJournal({id=job.id,status='started',action=job.action,args=job.args})
 local ok,result=pcall(execute,job)
 local out={type='result',id=job.id,ok=ok}
 if ok then out.data=result else out.error=tostring(result) end
 writeJournal({id=job.id,status='done',result=out})
 return out
end
function M.run(url)
 assert(http and http.websocket,'HTTP/WebSocket disabled')
 state.load()
 if url then saveURL(url) else url=configuredURL() end
 -- Reconcile a partially executed birth before connecting. The controller
 -- then receives the completed journal and can acknowledge it exactly once.
 local interrupted=readJournal()
 local active=state.data.birth
 if active and active.jobId and
    (interrupted.id==active.jobId or not interrupted.id) then
  if interrupted.status=='started' or
    (interrupted.status=='done' and
     interrupted.result and interrupted.result.ok==false) then
   print('Resuming unfinished first birth '..tostring(active.jobId))
   M.handle({id=active.jobId,action='birth',args=interrupted.args or {}})
  end
 end
 -- An M2 bootstrap resumed after reboot must only proceed when the turtle
 -- is at its saved home. The bootstrap routine checks this before movement.
 local base=state.data.bootstrap
 if base and not base.complete and base.jobId
    and interrupted.id==base.jobId and interrupted.action=='bootstrap' then
  if interrupted.status=='started' or
     (interrupted.status=='done' and interrupted.result
       and interrupted.result.ok==false) then
   M.handle({id=base.jobId,action='bootstrap',args=interrupted.args or {}})
  end
 end
 while true do
  local ok,err=pcall(function()
   local ws,reason=http.websocket(url)
   assert(ws,'Controller unavailable: '..tostring(reason))
   ws.send(textutils.serializeJSON({type='hello',id=os.getComputerID(),
      generation=state.data.generation,snapshot=snapshot(),journal=readJournal()}))
   while true do
    local msg=ws.receive(30)
    if msg then
     local data=textutils.unserializeJSON(msg)
     if type(data)=='table' then
      if data.type=='job' then
       ws.send(textutils.serializeJSON(M.handle(data)))
       ws.send(textutils.serializeJSON({type='snapshot',snapshot=snapshot()}))
      elseif data.type=='welcome' then
       print('Controller joined; recovery: '..tostring(data.recovery))
      end
     end
    else
     ws.send(textutils.serializeJSON({type='snapshot',snapshot=snapshot()}))
    end
   end
  end)
  if not ok then print('Controller: '..tostring(err)) end
  sleep(5)
 end
end
return M
