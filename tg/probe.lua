local M = {}
local function equipped(side)
  local fn = side == 'left' and turtle.getEquippedLeft or turtle.getEquippedRight
  if not fn then return 'not supported by installed CC version' end
  local data = fn()
  return data and data.name or 'none'
end
function M.run()
  print('Turtle Genesis API probe')
  print('Computer ID:', os.getComputerID(), 'CraftOS:', os.version())
  print('Fuel:', turtle.getFuelLevel(), '/', turtle.getFuelLimit())
  print('Left upgrade:', equipped('left'))
  print('Right upgrade:', equipped('right'))
  for _, side in ipairs({'front', 'back', 'left', 'right', 'top', 'bottom'}) do
    local typ = peripheral.getType(side)
    if typ then
      print(side .. ': ' .. tostring(typ))
      if typ == 'drive' and disk.isPresent(side) then
        print('  media:', tostring(disk.getMountPath(side)))
      end
    end
  end
  print('Inventory:')
  for i = 1, 16 do
    local detail = turtle.getItemDetail(i)
    if detail then print(i, detail.name, detail.count) end
  end
end
return M
