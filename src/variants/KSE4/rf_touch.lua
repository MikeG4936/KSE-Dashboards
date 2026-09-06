local function profilePointInBatteryTarget(wgt, touchState)
  if type(touchState) ~= "table" then return false end
  local x, y = tonumber(touchState.x), tonumber(touchState.y)
  local bar = V.bottom
  return x and y and bar
         and x >= bar.x and x < bar.x + bar.w
         and y >= bar.y and y < bar.barY + bar.barH + math.max(8, G.y(20))
end
