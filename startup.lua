-- Genesis startup: join inherited controller if configured; otherwise
-- retain the verified legacy boot path for already-installed turtles.
if fs.exists('/tg/worker-config.dat')
   and fs.exists('/tg/worker.lua')
   and fs.exists('/tg/worker-entry.lua') then
  shell.run('/tg/worker-entry.lua')
else
  local ok,err=shell.run('/tg/main.lua','boot')
  if not ok then printError('Genesis boot failed: '..tostring(err)) end
end
