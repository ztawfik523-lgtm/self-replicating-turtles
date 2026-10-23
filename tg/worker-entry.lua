-- Worker entry point intentionally separate from the legacy main program.
-- Worker itself restores state and reconnects to the Python controller.
local ok,err=pcall(function()
 require('worker').run()
end)
if not ok then printError('Genesis worker failed: '..tostring(err)) end
