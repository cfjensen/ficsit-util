FLN_PORT = 66 -- port for FLN communication
UPDATE_TIME_S = 1.0 -- time between updating the network

-- freight platforms do not follow usual rules
FREIGHT_PLATFORM_FLUID_MAX = 2400.0
FREIGHT_PLATFORM_FLUID_DIV = 1000.0

SCREEN_WIDTH = 20
SCREEN_HEIGHT = 4

FW_VERSION = 1.00

-- size of a table
function TableSize(t)
  local i = 0
  for _, _ in pairs(t) do
    i = i + 1
  end
  return i
end

-- print a table
function PrintTable(t)
  for k, v in pairs(t) do
    print(tostring(k) .. ": " .. tostring(v))
  end
end

-- Find attached inventories
function FindStorage(nodes)
  local storage = {}
  for _, node in pairs(nodes) do
    local ns = tostring(node)

    -- computers have inventory that's useless
    if ns == "Computer_C" then
      -- ignore

    -- iterate over all train platforms
    elseif ns == "Build_TrainStation_C" then
      while node do
        if #node:getInventories() ~= 0 then table.insert(storage, node) end
        node = node:GetConnectedPlatform()
      end

    -- otherwise, include if it can store solids or fluids
    elseif #node:getInventories() ~= 0 or node.maxFluidContent then
      table.insert(storage, node)
    end
  end

  return storage
end

-- check for total stacks, fluid storage, and any items that may be in the system
function GetMaxCapacity(nodes)
  local stacks = 0
  local fluid = 0
  local items = {}
  for _, node in pairs(nodes) do
    -- check first inventory
    local inv = node:getInventories()[1]
    if inv then
      -- fluid freight platforms do not behave like other fluid storage
      if tostring(node) == "Build_TrainDockingStationLiquid_C" then
        fluid = fluid + FREIGHT_PLATFORM_FLUID_MAX
      else
        stacks = stacks + inv.size
      end
      for i = 0, inv.size - 1 do
        local stk = inv:getStack(i)
        if stk.count > 0 then items[stk.item.type.name] = stk.item.type end
      end
    end

    -- check fluid storage
    if node.maxFluidContent then 
      fluid = fluid + node.maxFluidContent
      if node:getFluidType() then items[node:getFluidType().name] = node:getFluidType() end
    end
  end

  return stacks, fluid, items
end

-- check for current quantity of items in the system
function GetQty(nodes)
  total = 0
  for _, node in pairs(nodes) do
    if node.fluidContent then
      total = total + node.fluidContent
    else
      local inv = node:getInventories()[1]
      if not inv then
        --no inventory
      elseif inv.size == 1 then
        total = total + inv.itemCount / FREIGHT_PLATFORM_FLUID_DIV
      else
        total = total + inv.itemCount
      end
    end
  end
  return total
end

-- serialize a table into a string
function ser(t)
  local s = ""
  for k, v in pairs(t) do
    if type(v) == "table" then
      s = s .. tostring(k) .. ":{;" .. ser(v)
    else
      s = s .. tostring(k) .. ":" .. tostring(v) .. ";"
    end
  end
  return s .. "}"
end

-- deserialize a string into a table.  
function des(s)
  local t = {}
  local k, v
  while string.sub(s, 1, 1) ~= "}" do
    _, _, k, v, s = string.find(s, "(.-):(.-);(.*)")
    if v == "{" then v, s = des(s) end
    if tonumber(k) then k = tonumber(k) end
    if tonumber(v) then v = tonumber(v) end
    if v == "true" then v = true elseif v == "false" then v = false end
    t[k] = v
  end
  return t, string.sub(s, 2, -1)
end
-- print out contents of an object
function PrintInventory(obj)
  print("Inventory for: ", obj)
  local invs = obj:getInventories()
  for i, inv in ipairs(invs) do
    print("Inventory ", i, "Size", inv.size, "Total", inv.itemCount)
    for j = 0, inv.size - 1 do
      local stack = inv:getStack(j)
      if stack.count > 0 then print(stack.item.type.name, stack.count) end
    end
  end
  print("------")
end

-- find the length of the attached train station
function TrainStationLength(station, dir)
  local len = 0;
  while station do
    len = len + 1
    station = station:getConnectedPlatform(dir)
  end
  return len
end

-- find a stop on a train network based on hash
function FindStation(hash)
  for _, stop in pairs(station:getTrackGraph():getStations()) do
    if stop.hash == hash then return stop end
  end
  return nil
end

-- wrap a string to a character boundary
-- return modified string and number of lines
function WrapStr(s, nchar)
  local i = 1
  local w = 1
  local l = 1
  while s:sub(i, i) ~= "" do
    i = i + 1
    w = w + 1
    if (w >= nchar) then
      while s:sub(i, i) ~= " " do
        i = i - 1
        w = w - 1
      end
      s = s:sub(1, i - 1) .. "\n" .. s:sub(i + 1)
      w = 1
      l = l + 1
    end
  end
  return s, l
end

-- producer specific functions

-- get station info
function StationInfo()
  local info = {}
  info.cmd = "set_prod_info"
  info.item = item
  info.length = station_len
  info.stack = stack_size
  info.capacity = capacity
  return info
end

-- ensure train has schedule to only completely load at current station
function CleanSchedule(train)
  local sch = train:getTimeTable()
  local definition = 1
  if min_load > 0 then definition = 0 end
  
  while sch.numStops > 0 do
    sch:removeStop(0)
  end
  sch:addStop(0,
    station,
    {definition = definition, duration = 0.0, isDurationAndRule = true})
end

function FindReady()
  for _, train in ipairs(station:getTrackGraph():getTrains()) do
    if not train.isSelfDriving 
        and train:getTimeTable().numStops == 1
        and train:getTimeTable():getStop(0).station == station then
      return train
    end
  end
end

function UpdateText(item, qty)
  if qty == 0 then qty = "Full" end
  local s, l = WrapStr(item, SCREEN_WIDTH)
  s = s .. string.rep("\n", SCREEN_HEIGHT - l) .. qty
  text.text = s
end

do -- Register devices
  -- find the station and length
  station = component.findComponent(findClass("Build_TrainStation_C"))[1]
  if not station then computer.panic("No Station Found") end
  station = component.proxy(station)
  freight_platforms = {}
  local plat = station:getConnectedPlatform(0)
  while plat do
    table.insert(freight_platforms, plat)
    plat = plat:getConnectedPlatform(0)
  end
  station_len = TrainStationLength(station, 0)
  docked_train = nil
  last_train = nil

  nodes = component.proxy(component.findComponent(""))
  stores = FindStorage(nodes)
  stacks = 0
  fluid = 0
  item = nil

  -- attached items
  nic = computer.getPCIDevices(findClass("NetworkCard"))[1]
  _, _, nic_addr = string.find(tostring(nic), ".*%s(.*)")
  panel = component.proxy(component.findComponent(findClass("LargeControlPanel"))[1])
  text = panel:getModule(2, 10)
  gauge = panel:getModule(7, 10)
  led_en = panel:getModule(9, 10)
  led_dis = panel:getModule(9, 9)
  lever = panel:getModule(10, 10)
  enc = panel:getModule(1, 9)
  
  event.ignoreAll()
  event.clear()
  event.listen(lever)
  event.listen(enc)
  event.listen(nic)
  nic:open(FLN_PORT)

  dispatch = nil
  seq = 0
  
end

-- Initialize to starting values
function Init()
  print("Init")
  text.size = 37
  text.monospace = true
  gauge.limit = 1.0
  text.text = ""
  gauge.percent = 0
  lever.state = false
  led_en:setColor(0, 0, 0, 0)
  led_dis:setColor(1, 0, 0, 1)
  
  item = ""
  min_load = 0
  running = false
  capacity = 0
  stack_size = 0
end

-- save persistent train station info
function Save()
  local sdata = {item = item,
                 min_load = min_load,
                 running = running,
                 capacity = capacity,
                 stack_size = stack_size}
  panel.nick = ser(sdata)
end

-- restore persistent train station info and resolve with current world state
function Restore()
  local sdata = des(panel.nick)
  item = sdata.item
  min_load = sdata.min_load
  running = sdata.running
  capacity = sdata.capacity
  stack_size = sdata.stack_size
  
  ready_train = FindReady()
end

if lever.state then
  Restore()
else
  Init()
end

t = computer.millis()
while true do
  evt, src, netsrc, port, netdata, optdata = event.pull(UPDATE_TIME_S)
  
  -- check for a new docked train
  -- TODO better way of sensing if this is outgoing or incoming train
  if station:getDockedLocomotive() then
    docked_train = station:getDockedLocomotive():getTrain()
    if min_load ~= 0 and docked_train:getTimeTable().numStops == 2 then docked_train = nil end
  else
    docked_train = nil
  end
  if docked_train and not last_train then
    docked_train:setSelfDriving(false)
    CleanSchedule(docked_train)
  elseif last_train and not docked_train then
    ready_train = last_train
  end
  last_train = docked_train

  -- lever pull to turn system on
  if src == lever then
    if lever.state and item ~= "" then
      running = true
      Save()
      nic:send(dispatch, FLN_PORT, ser(StationInfo()))
      led_en:setColor(0, 1, 0, 1)
      led_dis:setColor(0, 0, 0, 0)
    else
      running = false
      lever.state = false
      ready_train = nil
      led_en:setColor(0, 0, 0, 0)
      led_dis:setColor(1, 0, 0, 1)
    end
    
  -- encoder to change the minimum train load
  elseif src == enc and not running and stack_size ~= 0 then
    min_load = min_load + netsrc * stack_size
    if min_load < 0 then min_load = 0 end
    UpdateText(item, min_load)

  elseif src == nic then
    local msg = des(netdata)
    seq = seq + 1
    print("Message " .. seq .. " from: " .. netsrc)
    PrintTable(msg)
    print("")

    -- set dispatch command received, send station info if available
    if msg.cmd == "set_dispatch" then
      print("Registered " .. netsrc .. " as Dispatcher")
      dispatch = netsrc
      if running then
        nic:send(dispatch, FLN_PORT, ser(StationInfo()))
        UpdateText(item, min_load)
      end
      
    -- send a train
    elseif msg.cmd == "send_train" then
      local dst_station = FindStation(msg.stop)
      if ready_train and dst_station then
        -- let the station know a supply train is coming
        local qty = GetQty(ready_train:getVehicles())
        if min_load ~= 0 then
          qty = qty + GetQty(freight_platforms)
          local max_qty = GetMaxCapacity(ready_train:getVehicles()) * stack_size
          if qty > max_qty then qty = max_qty end
        end
        nic:send(msg.nic, FLN_PORT, ser({
          cmd = "incoming_train",
          train = ready_train.hash,
          item = item,
          qty = qty}))
          
        -- add stop to the ready train's schedule and turn on
        local sch = ready_train:getTimeTable()
        sch:addStop(1, dst_station, {
          definition = 1,
          duration = 0.0,
          isDurationAndRule = true})
        if min_load == 0 then sch:setCurrentStop(1)
        else sch:setCurrentStop(0) end
        ready_train:setSelfDriving(true)
        ready_train = nil
      end
      
    -- device firmware upgrade
    elseif msg.cmd == "dfu_prod" then
      computer.setEEPROM(optdata)
      computer.reset()
    
    end -- NIC messages
  end
    
    -- periodic updates
  if computer.millis() - t > (UPDATE_TIME_S * 1000) then
    t = computer.millis()
    
    qty = GetQty(stores)
    gauge.percent = qty / capacity

    -- find dispatch server
    if not dispatch then
      nic:broadcast(FLN_PORT, ser({cmd = "get_dispatch"}))
      text.text = "No Dispatch Server"
      
    -- check inventory capacity / item availability
    elseif not running then
      stacks, fluid, items = GetMaxCapacity(stores)
      if TableSize(items) > 1 then
        text.text = "Error: Mixed Items"
      elseif TableSize(items) == 0 then
        text.text = "Error: No Item Found"
      else
        for _, v in pairs(items) do
          item = v
        end
        if fluid > 0 then
          capacity = fluid
          stack_size = 0
        else
          capacity = stacks * item.max
          stack_size = item.max
        end
        item = item.name
        UpdateText(item, min_load)
      end
    
    -- train is ready to go, send to dispatch
    elseif ready_train then
      local qty = GetQty(ready_train:getVehicles())
      local full_load = (min_load == 0)
      if min_load ~= 0 then
        qty = qty + GetQty(freight_platforms)
        local max_qty = GetMaxCapacity(ready_train:getVehicles()) * stack_size
        if qty > max_qty then
          qty = max_qty
          full_load = true
        end
      end
      if min_load == 0 or qty > min_load then
        nic:send(dispatch, FLN_PORT, ser(
         {cmd = "train_ready",
          length = station_len,
          item = item,
          qty = qty,
          full = full_load}))
      end
        
    end
  end
end
