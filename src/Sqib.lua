
-- Sqib, a sequence processing facility
-- Copyright 2020 psmay
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
-- documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
-- Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
-- WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
-- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-- Sqib unofficially stands for "Sequence Query for Impatient Bas^H^H^HFools".

local SqibBase = {}
function SqibBase:new(o)
  -- This implementation is directly from the Lua book 5.0.
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

local Sqib = SqibBase:new()


-- Iterable is the abstract base class.
-- An Iterable implementation must include an implementation of o:ipairs().
Sqib.Iterable = {}
local Iterable = Sqib.Iterable

-- This is the base constructor.
function Iterable:new(o)
  -- This implementation is directly from the Lua book 5.0.
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end




-- Returns a closure-based iterator over this sequence. The index starts with 1 for the first iteration and increases
-- by 1 for each subsequent iteration.
function Iterable:ipairs()
  error("ipairs() method is not implemented")
end

-- Returns a closure-based iterator over this sequence, where the index returned by each iteration is non-nil but
-- otherwise not defined. This is for simplifying implementations where the index would otherwise need to be tracked
-- explicitly.
--
-- By default, this returns the same as o:ipairs().
--
-- o:ipairs() must return the same sequence of values as this method, but with the index starting at 1 and increasing by
-- 1 each iteration.
function Iterable:ipairs_with_undefined_index()
  return self:ipairs()
end


local DefinedIndexIterable = Iterable:new()

function DefinedIndexIterable:ipairs()
  return self._ipairs()
end

local UndefinedIndexIterable = Iterable:new()

function UndefinedIndexIterable:ipairs()
  local iterator = self:ipairs_with_undefined_index()
  local out_index = 0
  return function()
    local i, v = iterator()
    if i ~= nil then
      out_index = out_index + 1
      return out_index, v
    end
  end
end

function UndefinedIndexIterable:ipairs_with_undefined_index()
  return self._ipairs_with_undefined_index()
end



-- Copies this sequence into a new table.
function Iterable:to_list()
  local copy = {}
  for i, v in self:ipairs() do
    copy[i] = v
  end
  return copy
end

-- Copies this sequence into a new table in the table.pack() format; 
function Iterable:pack()
  local copy = {}
  local n = 0
  for i, v in self:ipairs() do
    n = i
    copy[i] = v
  end
  copy.n = n
  return copy
end

-- Forces deferred evaluation of this sequence.
function Iterable:force()
  local a = self:to_list()
  return Sqib:from_list(a, true)
end

-- Creates a new table using the provided selectors to determine the keys and values.
-- key_selector(v, i) selects the key for an item. Default selects the value.
-- value_selector(v, i) selects the value for an item. Default selects the value.
-- An error is raised if any item produces nil as a key.
-- An error is raised if any key appears more than once.
function Iterable:to_hash(key_selector, value_selector)
  if key_selector == nil then
    key_selector = function(v)
      return v
    end
  end

  if value_selector == nil then
    value_selector = function(v)
      return v
    end
  end

  local seen = {}
  local hash = {}

  for i, v in self:ipairs() do
    local key = key_selector(v, i)
    if key == nil then
      error("nil cannot be used as a key")
    end
    if seen[key] then
      error("Key '" .. key .. "' encountered more than once")
    end
    seen[key] = true
    hash[key] = value_selector(v, i)
  end

  return hash
end




local function rx(ipairs_with_undefined_index_function)
  local s = UndefinedIndexIterable:new()
  s._ipairs_with_undefined_index = ipairs_with_undefined_index_function
  return s
end

local function ix(ipairs_function)
  local s = DefinedIndexIterable:new()
  s._ipairs = ipairs_function
  return s
end


local function noop()
end

function Iterable:map(selector)
  local source = self

  return rx(
    function()
      local iterator = source:ipairs_with_undefined_index()
      return function()
        local i, v = iterator()
        if i ~= nil then
          return i, selector(v, i)
        end
      end
    end
  )
end

function Iterable:flat_map(selector)
  local source = self

  return rx(
    function()
      local iterator = source:ipairs_with_undefined_index()

      local current_iterator

      return function()
        while true do
          -- Ensure that current_iterator is populated
          if current_iterator == nil then
            local ii, iv = iterator()
            if ii == nil then
              return
            end
            local subsequence = selector(iv, ii)
            current_iterator = subsequence:ipairs_with_undefined_index()
          end

          -- Get the next value from current_iterator
          local i, v = current_iterator()
          if i ~= nil then
            return -1, v
          else
            -- The current iterator is exhausted
            current_iterator = nil
          end
        end
      end
    end
  )
end

function Iterable:filter(predicate)
  local source = self

  return rx(
    function()
      local iterator = source:ipairs_with_undefined_index()

      return function()
        while true do
          local i, v = iterator()
          if i == nil then
            break
          elseif predicate(v, i) then
            return -1, v
          end
        end
      end
    end
  )
end

-- key_selector(v, i) returns the key by which to determine uniqueness.
-- If key_selector is omitted, the key selector returns the value.
-- An error is raised if any key is nil.
function Iterable:unique(key_selector)
  local source = self
  if key_selector == nil then
    key_selector = function(v)
      return v
    end
  end

  return rx(
    function()
      local iterator = source:ipairs_with_undefined_index()
      local seen = {}

      return function()
        while true do
          local i, v = iterator()
          if i == nil then
            break
          end

          local key = key_selector(v, i)
          if key == nil then
            error("nil cannot be used as a key")
          end

          if not seen[key] then
            seen[key] = true
            return -1, v
          end
        end
      end
    end
  )
end

function Iterable:take(count)
  local source = self
  count = math.floor(count)

  if count <= 0 then
    return simple(EMPTY)
  end

  return ix(
    function()
      local iterator = source:ipairs_with_undefined_index()
      local out_index = 0

      return function()
        if out_index < count then
          local i, v = iterator()
          if i ~= nil then
            out_index = out_index + 1
            return out_index, v
          end
        end
      end
    end
  )
end

function Iterable:take_while(predicate)
  local source = self

  return rx(
    function()
      local iterator = source:ipairs_with_undefined_index()
      local taking = true

      return function()
        if taking then
          local i, v = iterator()
          if i ~= nil and predicate(v, i) then
            return -1, v
          else
            taking = false
          end
        end
      end
    end
  )
end

function Iterable:skip_while(predicate)
  local source = self

  return rx(
    function()
      local iterator = source:ipairs_with_undefined_index()
      local skipping = true

      return function()
        local i, v

        if skipping then
          while skipping do
            i, v = iterator()
            if i == nil then
              skipping = false
              return
            elseif not predicate(v, i) then
              skipping = false
              break
            end
          end
        else
          i, v = iterator()
        end

        if i ~= nil then
          return -1, v
        end
      end
    end
  )
end

function Iterable:skip(count)
  local source = self
  count = math.floor(count)

  if count <= 0 then
    return source
  end

  return ix(function()
    local iterator = source:ipairs_with_undefined_index()

    local out_index = -count

    return function()
      while true do
        local i, v = iterator()
        if i == nil then
          break
        else
          out_index = out_index + 1
          if out_index >= 1 then
            return out_index, v
          end
        end
      end
    end
  end
  )
end


function SqibBase:from(...)
  return Sqib:from_list({...})
end

function SqibBase:empty()
  -- Subject to optimization
  return Sqib:from()
end

function SqibBase:from_ipairs(a)
  return ix(
    function()
      local iterator, invariant, control = ipairs(a)
      return function()
        local i, v = iterator(invariant, control)
        control = i
        if i ~= nil then
          return i, v
        end
      end
    end
  )
end


function SqibBase:from_list(a, should_cache_size)
  if should_cache_size == nil then
    should_cache_size = true
  end
  if should_cache_size then
    return ix(
      function()
        local i = 0
        local size = #a

        return function()
          i = i + 1
          if i <= size then
            return i, a[i]
          end
        end
      end
    )
  else
    return ix(
      function()
        local i = 0

        return function()
          i = i + 1
          if i <= #a then
            return i, a[i]
          end
        end
      end
    )
  end
end

return Sqib
