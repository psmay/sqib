
print(arg[0])

local Sqib = require 'src/Sqib'
local pprint = require 'tests/pprint'





-- Demo


local function str(v)
  return "" .. (v == nil and "(nil)" or v)
end

local t = { 2, 4, nil, 8 }

print("---")

local q = Sqib.from_ipairs(t)

for i, v in q:ipairs() do
  print(i, v)
end

print("---")

local r = Sqib.from_list(t)

for i, v in r:ipairs() do
  print(i, v)
end

print("---")

local z = r:map(function(v) return "[" .. str(v) .. "]" end)

for i, v in z:ipairs() do
  print(i, v)
end

print("---")

local y = r:filter(function(v) return v == nil end)

for i, v in y:ipairs() do
  print(i, v)
end

print("---")

local first_two = r:take(2)

for i, v in first_two:ipairs() do
  print(i, v)
end

print("---qqqq")

local qqqq = r:take_while(function(v) return v ~= nil end)

for i, v in qqqq:ipairs() do
  print(i, v)
end

print("----zzzz")




local yyyy = { {'a', 'b'}, {'c', 'd'}, {'e', 'f'} }

print(pprint(yyyy))

local zzzz = Sqib.from_list(yyyy)




for i, v in zzzz:flat_map(Sqib.from_list):ipairs() do
  print(i, v)
end
