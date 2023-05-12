-- keep a buffer inventory in each consumer for this number of seconds
BUFFER_TIME = 120.0
-- only count items in transit to a fraction of the desired amount
-- helps with larger factories where items will always be in transit
TRANSIT_FACTOR = 0.5
-- possible fuel for nuclear reactors
NUCLEAR_FUEL = {"Uranium Fuel Rod", "Plutonium Fuel Rod"}


DIR_UPSTREAM = 0
DIR_DOWNSTREAM = 1
SCREEN_WIDTH = 20
SCREEN_HEIGHT = 4
NO_ITEM = "None"

-- print a table
function PrintTable(t)
  for k, v in pairs(t) do
    print(tostring(k) .. ": " .. tostring(v))
  end
end

function AppendUnique(l1, l2)
  for _, elt2 in ipairs(l2) do
    InsertUnique(l1, elt2)
  end
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

-- find the index of a value in a list
-- returns index or 0 on failure
function FindIndex(list, elt, f)
  if not f then f = function (x) return x end end
  for i, v in ipairs(list) do
    if elt == f(v) then return i end
  end
  return 0
end

-- insert an item if not present in the list
-- returns true if the element was inserted, false if it was already in the list
function InsertUnique(l, elt)
  for _, k in ipairs(l) do
    if k == elt then return false end
  end
  table.insert(l, elt)
  return true
end

-- llmit a value to between min, and max.  min or max can be nil, which does not limit.
function Limit(val, min_val, max_val)
  if min_val and val < min_val then val = min_val end
  if max_val and val > max_val then val = max_val end
  return val
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

-- Find the next node along a connection going in one direction
function FindNextConnection(connection, direction)
  if not connection.isConnected or connection.direction ~= direction then return nil end
  while connection do
    local next = connection:getConnected()
    local node_next = next.owner
    local conn_next = node_next:getFactoryConnectors()
    if #node_next:getInventories() ~= 0 or #conn_next ~= 2 then return next end
    connection = nil
    for _, conn in ipairs(conn_next) do
      if conn.isConnected and conn.direction == direction then
        connection = conn
      end
    end
  end

  return nil
end

-- check if a node is a maker (anything with a recipe)
function IsMaker(node)
  return pcall(function () return node:getRecipe() end)
end

-- check if a node is a storage container (for now just using "Storage" in the name)
function IsStorage(node)
  return string.find(tostring(node), "Storage") ~= nil
end

-- check if a node is a power plant
function IsPlant(node)
  return string.find(tostring(node), "Build_GeneratorNuclear_C") ~= nil
end

-- check if a node is a sink
function IsSink(node)
  for _, conn in ipairs(node:getFactoryConnectors()) do
    if conn.direction == DIR_DOWNSTREAM then return false end
  end
  return true
end

-- print a recipe
function PrintRecipe(recipe)
  print("Recipe: " .. recipe.name)
  print("Duration: " .. recipe.duration)
  for i, v in ipairs(recipe:getIngredients()) do
    print(v.type.name .. ": " .. v.amount)
  end
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

-- Get a table of items and total quantity from a node
-- Also returns the number of empty stacks
function GetItems(node)
  local items = {}
  local empty = 0
  if node.fluidContent and node:getFluidType()then
    items[node:getFluidType().hash] = (items[node:getFluidType().hash] or 0) + node.fluidContent
  else
    local inv = node:getInventories()[1]
    if not inv then 
      -- no inventory
      
    -- inventory size 1 is always a fluid container
    elseif inv.size == 1 then
      local stack = inv:getStack(0)
      if stack.count ~= 0 then 
        items[stack.item.type.hash] = (items[stack.item.type.hash] or 0) + stack.count / FREIGHT_PLATFORM_FLUID_DIV
      end
    else      
      for i = 0, inv.size - 1 do
        local stack = inv:getStack(i)
        if stack.count == 0 then
          empty = empty + 1
        else
          items[stack.item.type.hash] = (items[stack.item.type.hash] or 0) + stack.count
        end
      end
    end
  end
  return items, empty
end


CONSUMER_TYPE_MAKER = 1
CONSUMER_TYPE_STORAGE = 2
CONSUMER_TYPE_PLANT = 3
CONSUMER_TYPE_SINK = 4

-- Add an item to the item name -> hash -> type table
function AddItem(item)
  items[item.type.name] = item.type.hash
  items[item.type.hash] = item.type
end

items = {}
consumers = {}
splitters = {}
receivers = {}
nodes = {}
stores = {}
function SetupNetwork(connection, upstream)
  if not connection or not connection.owner then return {} end
  local node = connection.owner
  -- local prefix = string.rep("|--", #upstream)
  
  -- found an endpoint
  if IsMaker(node) or IsStorage(node) or IsPlant(node) or IsSink(node) then
  
    -- create the endpoint if not found in the hashtable
    local consumer = consumers[node.hash]
    if not consumer then
      consumer = {}
      consumers[node.hash] = consumer
      if not node.id then return {} end
      consumer.proxy = component.proxy(node.id)
    end
    
    -- create the notify list if not present
    local receiver = receivers[connection.hash]
    if not receiver then
      receiver = {notify = {}}
      receivers[connection.hash] = receiver
      event.listen(connection)
    end
    
    -- add splitters to notify on item reception.  
    for _, splitter in ipairs(upstream) do
      if InsertUnique(receiver.notify, splitter) then
        -- print(prefix .. "Notify", splitter.proxy.hash)
      end
    end
    
  return {connection}
  
  elseif tostring(node) == "CodeableSplitter_C" then
    -- don't let one network propegate into another
    if node.nick ~= "" and #upstream ~= 0 then return {} end
  
    local splitter = splitters[node.hash]
    
    -- new splitter, recursively search downstream and create node information
    if not splitter then
      splitter  = {}
      splitters[node.hash] = splitter
      splitter.proxy = node
      event.listen(node)
      
      -- print(prefix .. tostring(splitter.proxy.hash))
      
      -- find connections to either left or right
      table.insert(upstream, splitter)
      splitter.consumers = 
        SetupNetwork(FindNextConnection(node:getFactoryConnectors()[1], DIR_DOWNSTREAM), upstream)
      if #splitter.consumers > 0 then
        splitter.direction = 0
      else
        splitter.consumers = 
          SetupNetwork(FindNextConnection(node:getFactoryConnectors()[3], DIR_DOWNSTREAM), upstream)
        splitter.direction = 2
      end
      table.remove(upstream)
      
      -- no overflow connection means this is a terminal node
      -- otherwise, find all connectors down the overflow (middle)
      splitter.is_terminal = true
      splitter.downstream = {}
      local ds_conn = FindNextConnection(node:getFactoryConnectors()[2], DIR_DOWNSTREAM)
      if node:getFactoryConnectors()[2].isConnected then
        splitter.is_terminal = false
        splitter.downstream = 
          SetupNetwork(ds_conn, upstream)
      end
      
      AppendUnique(splitter.downstream, splitter.consumers)
      splitter.incoming = {}
      
    -- splitter exists, but we haven't finished setting it up.  There must be a loop
    -- in the network
    elseif not splitter.downstream then
      return {}
    
    -- node is set up but we came here through a different path, have all downstream nodes
    -- notify the upstream nodes
    else
      for _, conn in ipairs(splitter.downstream) do
        SetupNetwork(conn, upstream)
      end
    end
    
    return splitter.downstream
    
  else -- other connection, find all downstream nodes
    local n = nodes[node.hash]
    if not n then
      n = {}
      nodes[node.hash] = n
      
      if tostring(node) == "CodeableMerger_C" then
        table.insert(merges, node)
      end
      
      -- recursively search all downstream nodes
      for _, conn in ipairs(node:getFactoryConnectors()) do
        AppendUnique(n, SetupNetwork(FindNextConnection(conn, DIR_DOWNSTREAM), upstream))
      end 
    
    -- we havn't finished setting up this node, there's a loop so ignore this path
    elseif #n == 0 then
      
      return {}
    
    -- node is set up but we came here through a different path, have all downstream nodes
    -- notify the upstream nodes
    else
      for _, conn in ipairs(n) do
        SetupNetwork(conn, upstream)
      end
    end
    
    return n
    
  end
end

-- set up what consumers are demanding
function SetupConsumers()

  local plants = {}

  for _, consumer in pairs(consumers) do
    local node = consumer.proxy
    
    -- add information about the recipe the the consumer node
    if IsMaker(node) and node:getRecipe() then
      consumer.type = CONSUMER_TYPE_MAKER
      consumer.stack = {}
      consumer.demand = {}
      local recipe = node:getRecipe()
      for i, ingredient in ipairs(recipe:getIngredients()) do
        AddItem(ingredient)
        consumer.stack[ingredient.type.hash] = i - 1
        consumer.demand[ingredient.type.hash] = ingredient.amount * 
         (1 + (BUFFER_TIME * node.potential / recipe.duration))
      end
      for _, product in ipairs(recipe:getProducts()) do
        AddItem(product)
      end
      
      -- print("Maker:", node.hash)
      -- print("Producing", node:getRecipe():getProducts()[1].type.name)
      
    -- Add storage specific information
    elseif IsStorage(node) then
      stores[node.hash] = consumer
      consumer.type = CONSUMER_TYPE_STORAGE
      consumer.demand = {}
      local inv = node:getInventories()[1]
      for i = 0, inv.size - 1 do
        local stack = inv:getStack(i)
        if stack.count > 0 then AddItem(stack.item) end
      end
      
    -- Queue up adding nuclear plant information
    elseif IsPlant(node) then
      table.insert(plants, consumer)
    
    -- Sink, request nothing and only notify upstream of incoming items
    else
      consumer.type = CONSUMER_TYPE_SINK
      consumer.demand = {}
    end
  end
  
  -- set up a single hash for nuclear fuel
  fuel_hash = nil
  fuel_table = {}
  for _, fuel in ipairs(NUCLEAR_FUEL) do
    if items[fuel] then
      fuel_hash = fuel_hash or items[fuel]
      fuel_table[items[fuel]] = fuel_hash
    else
      print("Fuel not found:", fuel)
    end
  end

  
  for _, consumer in ipairs(plants) do
    consumer.type = CONSUMER_TYPE_PLANT
    if not fuel_hash then computer.panic("No Nuclear Fuel Found") end
    consumer.demand = {}
    consumer.demand[fuel_hash] = 1
  end
end

producers = {}
function SetupProducers(connection)
  if not connection or not connection.owner then return {} end
  local node = connection.owner
  
  if IsMaker(node) then
    local producer = producers[node.hash]
    if not producer then
      local recipe = node:getRecipe()
      if not recipe then return {} end
      if not node.id then return {} end
      producer = {}
      producers[node.hash] = producer
      producer.proxy = component.proxy(node.id)

      for i, ingredient in ipairs(recipe:getIngredients()) do
        AddItem(ingredient)
      end
      local product = recipe:getProducts()[1]
      AddItem(product)
      producer.product = product.type.hash
      -- print("Producing: ", product.type.name)
    end
    
    return {producer}

  -- splitter / merger
  elseif tostring(node) ~= "CodeableSplitter_C" then
    local upstream = {}
    for _, conn in ipairs(node:getFactoryConnectors()) do
      AppendUnique(upstream, SetupProducers(FindNextConnection(conn, DIR_UPSTREAM)))
    end
    return upstream
  
  end
  
  return {}
end

-- create hashtable of item->possible consumers for each splitter
function OptimizeConsumers()
  for _, splitter in pairs(splitters) do
    splitter.check = {}
    
    -- for each downstream consumer, add all the items it could
    -- demand to the #item->consumer table for this splitter
    for _, conn in ipairs(splitter.consumers) do
      local consumer = consumers[conn.owner.hash]
      for item, _ in pairs(consumer.demand) do
        splitter.incoming[item] = 0
        if splitter.check[item] then
          InsertUnique(splitter.check[item], consumer)
        else
          splitter.check[item] = {consumer}
        end
      end
    end
    
    -- run the split/emit once to unstuck items
    if splitter.proxy.nick == "emit" then
      SmartEmit(splitter.proxy)
    else
      SmartSplit(splitter.proxy)
    end
    
  end
end

function OptimizeProducers()
  for _, producer in pairs(producers) do
    local store = FindStorage(producer.product)
    if store then
      producer.store = store
    end
  end
end

-- set up storage with information
stored_items = {}
function SetupStorage()
  -- find what item (and quantity, if any) should be stored in each storage
  for _, store in pairs(stores) do
    -- use what is currently in storage to determine demand
    for item, qty in pairs(GetItems(store.proxy)) do
      store.demand[item] = 0
      InsertUnique(stored_items, items[item].name)
    end
  
    local has_data, sdata = pcall(des, store.proxy.nick)
    if has_data and sdata then
      for item_name, qty in pairs(sdata) do
        if not items[item_name] then
          -- no items in storage, nor being produced.  we have no way of getting the item's
          -- hash or other info
          print("Error: could not identify item type:", item_name)
        else
          if qty ~= 0 then
            store.demand[items[item_name]] = qty
            InsertUnique(stored_items, item_name)
          end
        end
      end
    end
    
  end
  -- PrintTable(stored_items)
end

-- find the storage container for the given item
function FindStorage(item_req)
  for _, store in pairs(stores) do
    for item, _ in pairs(store.demand) do
      if item == item_req then return store end
    end
  end
  return nil
end

function UpdateText()
  local s, l = WrapStr(item_sel, SCREEN_WIDTH)
  s = s .. string.rep("\n", SCREEN_HEIGHT - l) .. qty_curr
  s = s .. string.rep(" ", SCREEN_WIDTH - (#tostring(qty_sel) + #tostring(qty_curr))) .. qty_sel
  text.text = s
end

-- Update item type/demand information
item_sel = NO_ITEM
qty_sel = 0
qty_curr = 0
qty_stack = 0
store_sel = nil
function UpdateUI(s, d)
  if type(d) == "boolean" then
    if d then d = -1 else d = 1 end
  end

  if s == enc_item then
    local i = FindIndex(stored_items, item_sel)
    i = Limit(i + d, 1, #stored_items)
    item_sel = stored_items[i]
    store_sel = FindStorage(items[item_sel])
  elseif s == enc_qty then
    if store_sel then
      qty_sel = Limit(qty_sel + d * qty_stack, 0)
      store_sel.demand[items[item_sel]] = qty_sel
      local sdata = {}
      for item, qty in pairs(store_sel.demand) do
        sdata[items[item].name] = qty
      end
      store_sel.proxy.nick = ser(sdata)
    end
  end
  
  if store_sel then
    qty_sel = store_sel.demand[items[item_sel]]
    qty_curr = GetQty(store_sel, items[item_sel])
    qty_stack = items[items[item_sel]].max
  else
    qty_sel = 0
    qty_curr = 0
    qty_stack = 0
  end

  UpdateText()
end

-- get the quantity and desired amount from a consumer for a particular item
function GetQty(consumer, item)
  if consumer.type == CONSUMER_TYPE_MAKER then
    return consumer.proxy:getInventories()[1]:getStack(consumer.stack[item]).count,
      consumer.demand[item]
  elseif consumer.type == CONSUMER_TYPE_STORAGE then
    return GetItems(consumer.proxy)[item] or 0, consumer.demand[item]
  elseif consumer.type == CONSUMER_TYPE_PLANT then
    -- nuclear plants always want 1 item in their inventory.  
    return consumer.proxy:getInventories()[2]:getStack(0).count, consumer.demand[item]
  end
  
  return 0, 0
end

-- split an incoming item to left or right if needed by a consumer, otherwise send it
-- down the center
function SmartSplit(s)
  local item = s:getInput()
  if not item.type then return end
  item = item.type.hash
  item = fuel_table[item] or item
  local split = splitters[s.hash]
  
  
  if not split.check[item] then
    if split.is_terminal then
      print("Clog detected: ", items[item].name)
    end
    s:transferItem(1) 
    return
  end
  
  local inv = 0
  local need = 0
  for _, consumer in ipairs(split.check[item]) do
    ci, cn = GetQty(consumer, item)
    if ci > cn then ci = cn end -- don't let overstock starve others
    inv = inv + ci
    need = need + cn
  end
  inv = inv + split.incoming[item] * TRANSIT_FACTOR
  
  
  if (split.is_terminal or need > inv) and s:transferItem(split.direction) then
    split.incoming[item] = split.incoming[item] + 1
  else
    s:transferItem(1)
  end
end

-- emit an item onto the bus only if needed
function SmartEmit(s)
  local item = nil
  for _, i in ipairs({1, 2, 0}) do
    local item = s:getInput(i)
    if item.type then
      item = item.type.hash
      item = fuel_table[item] or item
      local split = splitters[s.hash]
      
      local inv = 0
      local need = 0
      for _, consumer in ipairs(split.check[item]) do
        ci, cn = GetQty(consumer, item)
        if ci > cn then ci = cn end -- don't let overstock starve others
        inv = inv + ci
        need = need + cn
      end
      inv = inv + split.incoming[item]
      
      if need > inv and s:transferItem(i) then
        split.incoming[item] = split.incoming[item] + 1
        return
      end
    end
  end
end

function ConsumerInput(s, d)
  local receiver = receivers[s.hash]
  local item = d.type.hash
  item = fuel_table[item] or item
  for _, splitter in ipairs(receiver.notify) do
    splitter.incoming[item] = (splitter.incoming[item] or 0) - 1
    if splitter.incoming[item] < 0 then splitter.incoming[item] = 0 end
  end
end

function CheckProducers()
  for _, producer in pairs(producers) do
    if producer.store then
      qty, des = GetQty(producer.store, producer.product)
      if qty < des then
        producer.proxy.standby = false
      else
        producer.proxy.standby = true
      end
    else
      producer.proxy.standby = true
    end
  end
end

function Merge(e, s, d)
  s:transferItem(1)
  s:transferItem(2)
  s:transferItem(0)
end

event.ignoreAll()
event.clear()

do -- register components
  splits = component.proxy(component.findComponent("split"))
  emits = component.proxy(component.findComponent("emit"))
  prods = component.proxy(component.findComponent("prod"))
  merges = component.proxy(component.findComponent(findClass("CodeableMerger_C")))
  
  panel = component.proxy(component.findComponent(findClass("LargeControlPanel"))[1])
  text = panel:getModule(2, 10)
  enc_item = panel:getModule(1, 9)
  enc_qty = panel:getModule(6, 9)
  reset_btn = panel:getModule(10, 10)
  text.size = 37
  text.monospace = true
  event.listen(enc_item)
  event.listen(enc_qty)
  event.listen(reset_btn)
end

print("Setup Network")
for _, start in ipairs(splits) do
  SetupNetwork(start:getFactoryConnectors()[3], {})
end
for _, emit in ipairs(emits) do
  local splitter  = {}
  splitters[emit.hash] = splitter
  splitter.proxy = emit
  event.listen(emit)
  local ds_conn = FindNextConnection(emit:getFactoryConnectors()[4], DIR_DOWNSTREAM)
  splitter.consumers = SetupNetwork(ds_conn, {splitter})
  splitter.incoming = {}
end


SetupConsumers()
print("Setup Producers")
for _, start in ipairs(merges) do
  if start.nick == "prod" then SetupProducers(start:getFactoryConnectors()[3]) end
  event.listen(start) 
  if start.nick ~= "emit" then Merge(nil, start, nil) end
end
print("Optimize")
SetupProducers()
SetupStorage()
OptimizeConsumers()
OptimizeProducers()
table.sort(stored_items)
table.insert(stored_items, 1, NO_ITEM)
UpdateText()
CheckProducers()

t = computer.millis()
while true do
  e, s, d = event.pull(1.0)
  if s and s.nick == "emit" then SmartEmit(s)
  elseif tostring(s) == "CodeableSplitter_C" then SmartSplit(s)
  elseif tostring(s) == "CodeableMerger_C" then Merge(e, s, d)
  elseif tostring(s) == "FactoryConnection" then ConsumerInput(s, d)
  elseif tostring(s) == "MCP_Mod_Encoder_C" then UpdateUI(s, d)
  elseif tostring(s) == "ModulePotentiometer" then UpdateUI(s, d)
  elseif s == reset_btn then computer.reset()
  end
  if computer.millis() - t > (1 * 1000) then
    t = computer.millis()
    UpdateUI()
    CheckProducers()
    for _, emit in ipairs(emits) do SmartEmit(emit) end
  end
end


