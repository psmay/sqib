--[[

Sqib, a sequence query facility for Lua

Copyright © 2020 psmay

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

--]] --

--- Sqib, a sequence query facility for Lua
--
-- [This project is available on Github.](https://github.com/psmay/sqib)
--
-- @module Sqib
-- @author psmay
-- @license MIT
-- @copyright © 2020 psmay
-- @release 0.3.1-aa-20200804a

local Sqib = {
  _VERSION = "0.3.1-aa-20200804a"
}

--
-- nillable table functions
--

-- constant to represent nil
local function _NT_NIL_SURROGATE()
  return _NT_NIL_SURROGATE
end

-- nil-escape a possibly nil value
local function _nt_escape(v)
  return v == nil and _NT_NIL_SURROGATE or v
end

-- unescape a nil-escaped value
local function _nt_unescape(ev)
  if ev == _NT_NIL_SURROGATE then
    return nil
  else
    return ev
  end
end

-- add a value on an nt, returning true if added or false if key already exists
local function ntadd(t, k, v)
  local ek = _nt_escape(k)
  if t[ek] == nil then
    t[ek] = _nt_escape(v)
    return true
  else
    return false
  end
end

-- add a value f(...) to an nt, returning the existing value if it exists or the new value otherwise
local function ntaddselected(t, k, f, ...)
  local ek = _nt_escape(k)
  local ev = t[ek]
  if ev == nil then
    ev = _nt_escape(f(...))
    t[ek] = ev
  end
  return _nt_unescape(ev)
end

--
-- Utility local functions
--

local yield = coroutine.yield

local function passthrough(...)
  return ...
end

local function noop()
end

local function is_finite_number(x)
  return type(x) == "number" and not (x ~= x) and x ~= math.huge and x ~= -math.huge
end

local function is_integer(n)
  -- math.floor() seems to return the input value for non-integer "number"s such as inf, -inf, and NaN, so an extra
  -- check is done first
  return is_finite_number(n) and n == math.floor(n)
end

-- Wraps a function to pre-set its first parameters.
--
--    ff = bind(f, parameter1, parameter2)
--    -- equivalent to
--    ff = function(...) return f(parameter1, parameter2, ...) end
--
--    ff = bind(f)
--    -- equivalent to
--    ff = f
--
-- Note that the number of bound parameters is limited by Sqib.Seq:unpack().
local function bind(f, ...)
  if select("#", ...) > 0 then
    local bound_parameters = Sqib.over(...)
    return function(...)
      return f(bound_parameters:append(...):unpack())
    end
  else
    return f
  end
end

local function iterator_from_indexed_yielder(indexed_yielder)
  local co = coroutine.create(indexed_yielder)
  return function()
    local code, r2, r3 = coroutine.resume(co)
    if code then
      local index, value = r2, r3
      return index, value
    else
      local error_message = r2
      error(error_message)
    end
  end
end

local function seq_from_indexed_yielder(indexed_yielder)
  return Sqib.Seq:new {
    iterate = function()
      return iterator_from_indexed_yielder(indexed_yielder)
    end
  }
end

local function iterator_from_unindexed_yielder(unindexed_yielder)
  local sentinel = {}

  local wrapped_yielder = function()
    -- This wrap prevents the return from unindexed_yielder() from being returned from the resume.
    unindexed_yielder()
    -- This value marks the end of the sequence.
    return sentinel
  end

  local still_yielding = true
  local i = 0
  local co = coroutine.create(wrapped_yielder)
  return function()
    if still_yielding then
      local code, r = coroutine.resume(co)
      if code then
        local v = r

        if v == sentinel then
          still_yielding = false
        else
          i = i + 1
          return i, v
        end
      else
        local error_message = r
        error(error_message)
      end
    end
  end
end

local function seq_from_unindexed_yielder(unindexed_yielder)
  return Sqib.Seq:new {
    iterate = function()
      return iterator_from_unindexed_yielder(unindexed_yielder)
    end
  }
end

-- Iterator over a temporary array, where each element is deleted as it is read.
local function iterator_from_vanishing_array(a, n, reversed)
  if not is_integer(n) then
    error("Iterator over vanishing array failed; n must be an integer (got " .. type(n) .. ")")
  end

  local indexed_yielder

  if reversed then
    indexed_yielder = function()
      for out_index = 1, n do
        local i = n - (out_index - 1)
        local v = a[i]
        a[i] = nil
        yield(out_index, v)
      end
    end
  else
    indexed_yielder = function()
      for i = 1, n do
        local v = a[i]
        a[i] = nil
        yield(i, v)
      end
    end
  end

  return iterator_from_indexed_yielder(indexed_yielder)
end

-- Sqib.from(v) packaged as a selector.
local function selector_seq_from(v)
  return Sqib.from(v)
end

-- Internal implementation: Given `source`, a @{Sqib.Seq} of @{Sqib.Seq}, returns a @{Sqib.Seq} that is the
-- concatenation of the sequences. No selection or conversion is applied.
local function flatten(source)
  return seq_from_indexed_yielder(
    function()
      local out_index = 0

      for _, sv in source:iterate() do
        for _, v in sv:iterate() do
          out_index = out_index + 1
          yield(out_index, v)
        end
      end
    end
  )
end

-- Guesses the best way to convert `x` to a @{Sqib.Seq}, returning `nil` if it gives up.
local function try_seq_from(x)
  local type_x = type(x)
  if type_x == "table" then
    if type(x.is_sqib_seq) == "function" and x:is_sqib_seq() then
      return x
    elseif type(x.to_sqib_seq) == "function" then
      local seq = x:to_sqib_seq()
      if type(seq) == "table" and type(seq.is_sqib_seq) == "function" and seq:is_sqib_seq() then
        return seq
      else
        error("to_sqib_seq() returned a value that does not appear to be a Sqib sequence")
      end
    elseif is_integer(x.n) and x.n >= 0 then
      return Sqib.from_packed(x)
    else
      return Sqib.from_array(x)
    end
  elseif type_x == "function" then
    return Sqib.from_yielder(x)
  else
    return nil
  end
end

-- Converts the first `n` elements of `a` to @{Sqib.Seq} using `try_seq_from()`, raising an error if any element fails
-- to convert. Returns the concatenation of the results as a @{Sqib.Seq}.
local function seq_from_all(a, n)
  if not is_integer(n) then
    error("Sequence concatenation failed; parameter count must be an integer (got " .. type(n) .. ")")
  end
  if n <= 0 then
    return Sqib.empty()
  end

  local sequences = {}

  for i = 1, n do
    local s = try_seq_from(a[i])
    if s == nil then
      error("Parameter " .. i .. " has no automatic conversion to a sequence")
    end
    sequences[i] = s
  end

  if n == 0 then
    return Sqib.empty()
  elseif n == 1 then
    return sequences[1]
  else
    return flatten(Sqib.from_array(sequences, n))
  end
end

local function seq_from_pairs(t, result_selector)
  if result_selector == nil then
    result_selector = function(k, v)
      return {k, v}
    end
  end

  return seq_from_indexed_yielder(
    function()
      local out_index = 0
      for k, v in pairs(t) do
        out_index = out_index + 1
        yield(out_index, result_selector(k, v))
      end
    end
  )
end

local function iterator_from_array_slice(a, start, limit)
  -- Caller must ensure that start and limit are integers
  local offset = start - 1
  local adjusted_limit = limit - offset

  return iterator_from_indexed_yielder(
    function()
      for i = 1, adjusted_limit do
        yield(i, a[offset + i])
      end
    end
  )
end

local function seq_from_array_slice(a, start, limit)
  -- Caller must ensure that start and limit are integers
  if start <= limit then
    return Sqib.Seq:new {
      iterate = function()
        return iterator_from_array_slice(a, start, limit)
      end
    }
  else
    return Sqib.empty()
  end
end

local function seq_from_array(a, n)
  -- Caller must ensure that n is nil or an integer
  if n == nil then
    return Sqib.Seq:new {
      iterate = function()
        return iterator_from_array_slice(a, 1, #a)
      end
    }
  else
    return seq_from_array_slice(a, 1, n)
  end
end

local function seq_from_packed(t)
  return seq_from_indexed_yielder(
    function()
      local n = t.n
      if not is_integer(n) then
        error("Iterator over packed list failed; n must be an integer (got " .. type(n) .. ")")
      end
      for i = 1, n do
        yield(i, t[i])
      end
    end
  )
end

do
  -- This is lazy so that it can appear before Sqib.Seq:new() is defined.
  local get_empty_seq
  get_empty_seq = function()
    local EmptySeq = Sqib.Seq:new()

    function EmptySeq:iterate() -- luacheck: no self
      return noop
    end

    function EmptySeq:count() -- luacheck: no self
      return 0
    end

    get_empty_seq = function()
      return EmptySeq:new()
    end

    return get_empty_seq()
  end

  --- Returns a new @{Sqib.Seq} containing zero elements.
  --
  -- @return A new, empty @{Sqib.Seq}.
  function Sqib.empty()
    return get_empty_seq()
  end
end

--- Produces a @{Sqib.Seq} by guessing the appropriate conversion for `value`.
--
--  - If `value` is a table,
--     - If `value.is_sqib_seq` exists as a function and `value:is_sqib_seq()` returns true, `value` is used directly.
--     - If `value.to_sqib_seq` exists as a function, the result of `value:to_sqib_seq()` is used.
--       - If the value `seq` returned by `value:to_sqib_seq()` is not a table, or `seq.is_sqib_seq` is not a function,
--         or `seq:is_sqib_seq()` does not return true, an error is raised.
--     - Otherwise, if `value.n` exists as a nonnegative integer, the result of @{Sqib.from_packed}(value) is used.
--     - Otherwise, the result of @{Sqib.from_array}(value) is used.
--  - If `value` is a function, the result of @{Sqib.from_yielder}(value) is used.
--  - Otherwise, an error is raised.
--
-- @param value A source of sequence data to be used as a sequence.
-- @return A @{Sqib.Seq} obtained by automatically converting `value`.
-- @raise * When `value` has no automatic conversion to a sequence.
-- * When `value.to_sqib_seq` is a function but `value:to_sqib_seq()` returns a value that does not appear to be a
--   sequence (i.e., does not pass the `is_sqib_seq()` test).
-- @see Sqib.from_all
function Sqib.from(value)
  local s = try_seq_from(value)
  if s == nil then
    error("Value has no automatic conversion to a sequence")
  end
  return s
end

--- Produces a @{Sqib.Seq} by converting each parameter to a @{Sqib.Seq} and concatenating the results.
--
-- @param ... Sequence-like values to be converted to sequences (using the same rules as @{Sqib.from}) and concatenated.
-- @return A @{Sqib.Seq} obtained by automatically converting every parameter to a @{Sqib.Seq}, then concatenating the
-- results.
-- @raise * When any parameter has no automatic conversion to a sequence.
-- * When, for any parameter `v`, `v.to_sqib_seq` is a function but `v:to_sqib_seq()` returns a value that does not
--   appear to be a sequence (i.e., does not pass the `is_sqib_seq()` test).
-- @see Sqib.from
function Sqib.from_all(...)
  local n = select("#", ...)
  return seq_from_all({...}, n)
end

--- Returns a @{Sqib.Seq} based on an array or its first elements.
--
-- @param a An array on which to base the new sequence.
-- @param[opt] n The number of elements to include from `a`. If omitted, the length is recomputed from `#a` at the
-- beginning of each new iteration.
-- @return A @{Sqib.Seq} consisting of the first `n` elements of `a`, or, if `n` is omitted, the first `#a` elements of
-- `a`.
-- @see Sqib.from_array_slice
function Sqib.from_array(a, n)
  return seq_from_array(a, n)
end

--- Returns a @{Sqib.Seq} based on the elements of a subsequence of an array between two specified indexes.
--
-- @param a An array on which to base the new sequence.
-- @param start The inclusive index of `a` at which to start the sequence. Must be an integer, but need not be positive.
-- @param limit The inclusive index of `a` at which to end the sequence. Must be an integer, but need not be positive.
-- @return A @{Sqib.Seq} consisting of the elements of `a` from `a[start]` to `a[limit]`, inclusive, or an empty
-- sequence if `start` is greater than `limit`.
-- @see Sqib.from_array
function Sqib.from_array_slice(a, start, limit)
  if not is_integer(start) then
    error("Start index must be an integer")
  elseif not is_integer(limit) then
    error("Index limit must be an integer")
  end

  if start > limit then
    return Sqib.empty()
  else
    return seq_from_array_slice(a, start, limit)
  end
end

--- Returns a @{Sqib.Seq} based on the supplied iterate function.
--
-- The function `iterate` is expected to return an iterator function and optionally stateless iterator parameters.
-- `iterate` is used in a construction similar to `for _, v in iterate() do ... end` and has a similar contract to the
-- built-in `ipairs()` or `pairs()` functions.
--
-- The iteration is expected to produce each successive element of the represented sequence by returning either:
--
-- * a pair `x, v`, where `x` is any non-`nil` value and `v` is the next element value, or
-- * `nil`, signaling the end of the sequence.
--
-- The index values produced by the iterator need not be in any particular order; the requirement is only that each
-- index value be non-`nil` if a value is being returned or `nil` once the sequence is exhausted. The sequence returned
-- from this method discards the indexes from the iterator and provides its own indexes that comply with the contract of
-- `iterate`.
--
--    function example_iterate(start, limit)
--      local i = start - 1
--
--      return function()
--        if i < limit then
--          i = i + 1
--          return true, i
--        end
--      end
--    end
--
--    local seq = Sqib.from_iterate(example_iterate, 10, 13)
--    -- sequence is 10, 11, 12, 13
--
-- [Implementation detail: The number of parameters in `...` is subject to the same limitations as `unpack`.]
--
-- @param iterate A function which returns an iterator function.
-- @param[opt] ... Parameters that will be passed to `iterate` at the beginning of each new iteration.
-- @return A new @{Sqib.Seq} based on the abstract sequence traversed by `iterate`, with renumbered indexes.
-- @see Sqib.from_yielder
function Sqib.from_iterate(iterate, ...)
  local bound_iterate = bind(iterate, ...)

  return seq_from_indexed_yielder(
    function()
      local out_index = 0
      for _, v in bound_iterate() do
        out_index = out_index + 1
        yield(out_index, v)
      end
    end
  )
end

--- Returns a @{Sqib.Seq} based on the keys of a table.
--
-- @param t A table whose keys to traverse.
-- @return A new @{Sqib.Seq} representing the keys of `t`, in no particular order.
function Sqib.from_keys(t)
  return Sqib.from_pairs(
    t,
    function(k)
      return k
    end
  )
end

--- Returns a @{Sqib.Seq} based on a packed list.
--
-- For the purposes of this method, a packed list is a table `t` which has a field `t.n` that is a nonnegative integer
-- and which has elements `t[1]` through `t[t.n]` (any or all of which may be `nil`) that constitute a conceptual list.
-- This method produces a @{Sqib.Seq} representing this list.
--
-- @param t A packed list.
-- @return A new @{Sqib.Seq} based on the elements of the packed list `t`.
function Sqib.from_packed(t)
  return seq_from_packed(t)
end

--- Returns a @{Sqib.Seq} based on the key-value pairs of a table.
--
-- @param t A table whose key-value pairs to traverse.
-- @param[opt] result_selector A function `(k, v)` that selects the output element based on each key-value pair. If
-- omitted, the selector produces a two-element array `{k, v}` containing the key and the value.
-- @return A new @{Sqib.Seq} representing the key-value pairs of `t`, in no particular order.
function Sqib.from_pairs(t, result_selector)
  return seq_from_pairs(t, result_selector)
end

--- Returns a @{Sqib.Seq} based on the values of a table.
--
-- @param t A table whose values to traverse.
-- @return A new @{Sqib.Seq} representing the values of `t`, in no particular order.
function Sqib.from_values(t)
  return Sqib.from_pairs(
    t,
    function(_, v)
      return v
    end
  )
end

--- Returns a @{Sqib.Seq} based on the supplied yielder function.
--
-- The function `yielder` is expected to call `coroutine.yield(v)` once for each successive value `v` in the iteration.
-- `yielder` is called from a coroutine using the supplied parameters, if any, at the beginning of each new iteration.
--
--    function example_yielder(start, limit)
--      for i = start, limit do
--        for j = start, limit do
--          coroutine.yield("(" .. i .. "," .. j .. ")")
--        end
--      end
--    end
--
--    local seq = Sqib.from_yielder(example_yielder, 1, 2)
--    -- seq is "(1,1)", "(1,2)", "(2,1)", "(2,2)"
--
-- [Implementation detail: The number of parameters in `...` is subject to the same limitations as `unpack`.]
--
-- @param yielder A function which returns an iterator function.
-- @param[opt] ... Parameters that will be passed to `iterate` at the beginning of each new iteration.
-- @return A new @{Sqib.Seq} based on the abstract sequence traversed by `iterate`, with renumbered indexes.
function Sqib.from_yielder(yielder, ...)
  local bound_yielder = bind(yielder, ...)
  return seq_from_unindexed_yielder(bound_yielder)
end

--- Returns a @{Sqib.Seq} over the supplied sequence of parameters.
--
-- @param ... Elements to be traversed by the new sequence.
-- @return A new @{Sqib.Seq} based on the values of `...`.
function Sqib.over(...)
  local n = select("#", ...)
  if n == 0 then
    return Sqib.empty()
  end
  return Sqib.from_array({...}, n)
end

--- Returns a new @{Sqib.Seq} over the specified range.
--
-- The sequence produced is the same sequence produced by the `for` loop
--
--     for i=start_value, limit_value, step do ... end
--
-- @param start_value The initial value of the range.
-- @param limit_value The limit for the final value of the range.
-- @param[opt=1] step The step value for iteration.
-- @return A new @{Sqib.Seq} with contents based on the specified range.
function Sqib.range(start_value, limit_value, step)
  if step == nil then
    step = 1
  end

  return seq_from_indexed_yielder(
    function()
      local out_index = 0

      for i = start_value, limit_value, step do
        out_index = out_index + 1
        yield(out_index, i)
      end
    end
  )
end

--- Returns a new @{Sqib.Seq} that repeats a specified value a specified number of times.
--
-- @param value The element value to be repeated.
-- @param count The number of times to repeat `value`.
-- @return A new @{Sqib.Seq} consisting of `value` repeated `count` times.
function Sqib.times(value, count)
  count = math.floor(count)
  if count <= 0 then
    return Sqib.empty()
  else
    return seq_from_indexed_yielder(
      function()
        for i = 1, count do
          yield(i, value)
        end
      end
    )
  end
end

--- The abstract base class for Sqib sequences.
--
-- Derived classes must implement @{Sqib.Seq:iterate}. If a derived class can determine its own size in less-than-linear
-- time, it should also override @{Sqib.Seq:count}.
--
-- @type Sqib.Seq

Sqib.Seq = {}

--- The constructor for an abstract @{Sqib.Seq}.
--
-- The implementation of this method does nothing beyond creating the object and setting the type's index and the
-- instance's metatable.
--
-- See the functions of `Sqib` (for example, @{Sqib.from}) for simple ways to create @{Sqib.Seq} objects from actual
-- data.
--
-- @param[opt={}] o A table to convert into this type.
-- @return `o`, having been converted to this type.
function Sqib.Seq:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

--- Returns whether all elements of this sequence satisfy a predicate.
--
-- If this sequence is empty, returns `true`.
--
-- @param predicate A function `(v, i)` that returns true if the current element satisfies a condition or false
-- otherwise.
-- @return `true` if all elements of this sequence satisfy `predicate`, or `false` otherwise.
function Sqib.Seq:all(predicate)
  for i, v in self:iterate() do
    if not predicate(v, i) then
      return false
    end
  end
  return true
end

--- Returns whether this sequence contains any elements or contains any elements that satisfy a predicate.
--
-- If this sequence is empty, returns `false`.
--
-- @param[opt] predicate A function `(v, i)` that returns true if the current element satisfies a condition or false
-- otherwise.
-- @return If `predicate` is supplied, `true` if any element in this sequence satisfies `predicate`, or `false`
-- otherwise. If `predicate` is omitted, `true` if this sequence contains any elements, or `false` otherwise.
function Sqib.Seq:any(predicate)
  if predicate == nil then
    for _, _ in self:iterate() do -- luacheck: ignore 512
      return true
    end
  else
    for i, v in self:iterate() do
      if predicate(v, i) then
        return true
      end
    end
  end
  return false
end

--- Produces a @{Sqib.Seq} consisting of this sequence followed by the specified elements.
--
-- @param ... Elements to append to this sequence.
-- @return A @{Sqib.Seq} consisting of the elements of this sequence followed by the specified additional elements.
function Sqib.Seq:append(...)
  local n = select("#", ...)
  if n == 0 then
    return self
  else
    return seq_from_all({self, Sqib.over(...)}, 2)
  end
end

--- Produces a @{Sqib.Seq} consisting of this sequence's elements as blocks of a specified number of elements each.
--
-- Each block before the final block contains exactly `block_size` elements. The final block contains the remainder of
-- the sequence, which is as few as one element or as many as `block_size` elements. No block will ever contain zero
-- elements.
--
-- By default, the resulting sequence will produce each block as a packed list. If another form is more useful, specify
-- a `result_selector` that accepts an array and size and produces the desired element.
--
--    -- Example: Produces each block as a new Sqib.Seq
--    local seq_of_seq = seq:batch(block_size, function(a, n) return Sqib.from_array(a, n) end)
--
-- @param block_size The number of elements to include in each block. Must be a positive integer.
-- @param[opt] result_selector A function `(a, n)` to be applied to each block before it is returned from the iterator,
-- where `a` is an array containing the elements of the block and `n` is the number of elements in the block. If
-- omitted, the result selector defaults to returning a packed list (i.e. by setting `a.n` to `n` and returning `a`).
-- @return A @{Sqib.Seq} that iterates over this sequence `block_size` elements at a time.
function Sqib.Seq:batch(block_size, result_selector)
  if (not is_integer(block_size)) or (block_size < 1) then
    error("block_size must be a positive integer")
  end

  if result_selector == nil then
    result_selector = function(a, n)
      a.n = n
      return a
    end
  end

  local source = self

  return seq_from_indexed_yielder(
    function()
      local a = {}
      local n = 0
      local out_index = 0

      for _, v in source:iterate() do
        n = n + 1
        a[n] = v

        if n == block_size then
          out_index = out_index + 1
          yield(out_index, result_selector(a, n))
          a = {}
          n = 0
        end
      end

      if n > 0 then
        out_index = out_index + 1
        yield(out_index, result_selector(a, n))
      end
    end
  )
end

--- Calls the specified function as if it were a method on this sequence.
--
-- This is a simple way to call custom sequence operations fluently without assigning them directly to to @{Sqib.Seq}
-- table.
--
--    function my_every_n(seq, n)
--      return seq:filter(function(_,i) return i % n == 0 end)
--    end
--
--    -- Use call
--    local seq = Sqib.over(1,2,3,4,5,6,7,8,9,10)
--      :call(my_every_n, 3)
--    -- seq is now the sequence 3, 6, 9
--
-- @param f A function to call as if it were a method.
-- @param[opt] ... Additional parameters for `f`.
-- @return The result of calling `f(self, ...)`, where `self` is this sequence.
function Sqib.Seq:call(f, ...)
  return f(self, ...)
end

--- Returns a @{Sqib.Seq} consisting of this sequence followed by the specified additional sequences.
--
-- @param ... Sequence-like values to be converted to sequences (using the same rules as @{Sqib.from}) and concatenated
-- to this sequence.
-- @return A @{Sqib.Seq} consisting of the elements of this sequence followed by the elements of each of the specified
-- additional sequences.
-- @raise * When any parameter has no automatic conversion to a sequence.
-- * When, for any parameter `v`, `v:to_sqib_seq()` is found but returns a value that does not appear to be a sequence
-- (i.e., does not pass the `is_sqib_seq()` test).
-- @see Sqib.from
function Sqib.Seq:concat(...)
  local n = select("#", ...)
  if n == 0 then
    return self
  else
    return seq_from_all({self, ...}, n + 1)
  end
end

--- Copies all elements of this sequence into an existing array or object.
--
-- The first element of this sequence is copied to `a[start_index]`, the second to `a[start_index + 1]`, and so on. Any
-- values already in these positions are overwritten.
--
-- @param a An array or array-like object into which elements will be copied.
-- @param[opt=1] start_index The first index of `a` to use for copying elements. If provided, this must be an integer.
-- The value need not be positive (the caveats of using non-1-based arrays in Lua are well documented elsewhere).
-- @return The number of elements copied. (The copied elements are `a[start_index]` through `a[start_index - 1 + <number
-- of elements copied>]`.)
function Sqib.Seq:copy_into_array(a, start_index)
  if start_index == nil then
    start_index = 1
  elseif not is_integer(start_index) then
    error("start_index must be an integer")
  end

  local offset = start_index - 1
  local i = 0
  for _, v in self:iterate() do
    i = i + 1
    a[offset + i] = v
  end

  return i
end

--- Counts the number of elements, or the number of elements that satisfy a predicate, in this sequence.
--
-- @param[opt] predicate A function `(v, i)` that returns true if the current element satisfies a condition or false
-- otherwise. If omitted, all elements are counted.
-- @return The total number of elements (if `predicate` is omitted) or the number of elements that satisfy `predicate`
-- (if `predicate` is supplied) in this sequence.
function Sqib.Seq:count(predicate)
  local n = 0

  if predicate == nil then
    for _, _ in self:iterate() do
      n = n + 1
    end
  else
    for i, v in self:iterate() do
      if predicate(v, i) then
        n = n + 1
      end
    end
  end

  return n
end

--- Filters this sequence to only the elements that satisfy a predicate.
--
-- @param predicate A function `(v, i)` that returns true if the current element satisfies a condition or false
-- otherwise.
-- @return A new @{Sqib.Seq} consisting of the elements of this sequence that satisfy `predicate`.
function Sqib.Seq:filter(predicate)
  local source = self

  return seq_from_indexed_yielder(
    function()
      local out_index = 0

      for i, v in source:iterate() do
        if predicate(v, i) then
          out_index = out_index + 1
          yield(out_index, v)
        end
      end
    end
  )
end

--- Maps this sequence by applying a sequence-producing selector, then returns a sequence from the concatenated results.
--
-- @param[opt] selector A sequence-returning function `(v, i)` to apply to each element in the sequence. If omitted, the
-- selector returns the element value.
-- @param[opt=true] convert_result Indicates whether the value returned from the selector should be converted into a
-- @{Sqib.Seq} using @{Sqib.from}, which allows the operation to flatten certain other non-@{Sqib.Seq} sequences. Set to
-- `false` if the selector always produces a @{Sqib.Seq} and doesn't need the additional conversion.
-- @return A new @{Sqib.Seq} consisting of the concatenated elements of the sequences returned by `selector` as applied
-- to each element from this sequence.
function Sqib.Seq:flat_map(selector, convert_result)
  if convert_result == nil then
    convert_result = true
  end

  local source = self

  if selector ~= nil then
    source = source:map(selector)
  end

  if convert_result then
    source = source:map(selector_seq_from)
  end

  return flatten(source)
end

--- Forces immediate evaluation of this sequence.
--
-- This method iterates this sequence completely, making an immutable copy, and returns a @{Sqib.Seq} based on the copy.
--
-- The main effects of using the returned @{Sqib.Seq} in place of the original sequence are:
--
-- * The resulting sequence itself doesn't need to perform any non-trivial computations. Any (potentially intensive)
--   computation specified before the force only happens once.
-- * The resulting sequence will not vary between iterations, even if
--   * this source sequence is mutable (such as an array passed to @{Sqib.from}, if anything other than the sequence
--     still has a reference to it)
--   * this source sequence is based on computations which use variables that are themselves mutable
-- * The resulting sequence generally occupies more memory.
--
-- The effect of conversions such as @{Sqib.Seq:to_array} or @{Sqib.Seq:pack} is similar, except that those methods do
-- not directly produce a @{Sqib.Seq} while this method does not produce an object which can be accessed as a table.
--
-- @return A new @{Sqib.Seq} based on an immutable copy of the values from an immediate, full iteration of this
-- @{Sqib.Seq}.
function Sqib.Seq:force()
  local a, n = self:to_array(true)
  return Sqib.from_array(a, n)
end

--- Returns whether this object should be treated as @{Sqib.Seq}.
--
-- A function named `is_sqib_seq` on any object is assumed (e.g. by @{Sqib.from}) to return true if the object is a
-- @{Sqib.Seq} (or close enough to one that it can be treated as one). This method exists for the purpose of identifying
-- an object as a @{Sqib.Seq} in absence of any reliable way to do so in Lua.
--
-- The `is_sqib_seq` method of @{Sqib.Seq} is specified to always return `true`. This should not be overridden by
-- derived types of @{Sqib.Seq}.
--
-- @return `true`.
-- @see Sqib.Seq:to_sqib_seq
-- @see Sqib.from
function Sqib.Seq:is_sqib_seq() -- luacheck: no self
  return true
end

--- Returns a closure-based iterator over this sequence.
--
-- Each time the returned iterator is called, it returns a pair of values `i, v` (an index and a value, respectively)
-- that represent each successive element from the sequence, until the sequence is exhausted, at which point `i` will be
-- `nil`.
--
-- The index `i` is defined to start at 1 and increase by 1 with each new element.
--
-- @return A closure-based (non-stateless) iterator over this sequence.
function Sqib.Seq:iterate() -- luacheck: no self
  error("iterate() method is not implemented")
end

--- Maps each element of this sequence by applying a selector.
--
-- @param selector A function `(v, i)` to apply to each element in the sequence.
-- @return A new @{Sqib.Seq} consisting of the results of applying `selector` to each element of this sequence.
function Sqib.Seq:map(selector)
  local source = self

  return seq_from_indexed_yielder(
    function()
      for i, v in source:iterate() do
        yield(i, selector(v, i))
      end
    end
  )
end

--- Copies this sequence into a new packed list.
--
-- @return A new table containing the elements of this sequence, with a field `n` containing the length of the list.
function Sqib.Seq:pack()
  local copy, n = self:to_array(true)
  copy.n = n
  return copy
end

--- Creates a new dictionary-style table using the provided selector to determine each key-value pair.
--
-- @param pair_selector Function `(v, i)` that returns `k, v`, the key and value for a pair.
-- @return The newly created table.
-- @raise * When `pair_selector` is not provided.
-- * When any key appears more than once.
-- @see Sqib.Seq:to_hash
function Sqib.Seq:pairs_to_hash(pair_selector)
  if pair_selector == nil then
    error("Pair selector was not provided.")
  end

  local seen = {}
  local hash = {}

  for i, v in self:iterate() do
    local key, value = pair_selector(v, i)
    if seen[key] then
      error("Key '" .. key .. "' encountered more than once")
    end
    seen[key] = true
    hash[key] = value
  end

  return hash
end

--- Returns a new @{Sqib.Seq} that consists of the elements of this sequence in reverse order.
--
-- The reverse operation itself is deferred and occurs whenever the returned @{Sqib.Seq} is actually iterated. When an
-- iterator is retrieved, the entire contents of the source sequence are copied into an internal table. The resulting
-- element values are iterated in reverse order.
--
-- @return A @{Sqib.Seq} representing a copy of this sequence whose elements have been reversed.
function Sqib.Seq:reversed()
  local source = self

  return Sqib.Seq:new {
    iterate = function()
      local a, n = source:to_array(true)
      return iterator_from_vanishing_array(a, n, true)
    end
  }
end

--- Skips a specified number of elements, then produces the remainder.
--
-- @param count A number of elements to skip. If this is zero or less, the result is the entire sequence. If this is the
-- length of the sequence or greater, the result is empty.
-- @return A @{Sqib.Seq} consisting of the elements of this sequence after the first `count` elements have been skipped.
function Sqib.Seq:skip(count)
  local source = self
  count = math.floor(count)

  if count <= 0 then
    return source
  end

  return seq_from_indexed_yielder(
    function()
      local out_index = -count

      for _, v in source:iterate() do
        out_index = out_index + 1
        if out_index >= 1 then
          yield(out_index, v)
        end
      end
    end
  )
end

--- Skips all elements while a predicate is satisfied, then produces the remainder.
--
-- @param predicate A function `(v, i)` to test elements. Elements are skipped until the first element for which this
-- returns false; the remaining elements are passed through untested.
-- @return A @{Sqib.Seq} consisting of all elements of this sequence including and after the first element for which the
-- predicate returns false.
function Sqib.Seq:skip_while(predicate)
  local source = self

  return seq_from_indexed_yielder(
    function()
      local out_index = 0
      local skipping = true

      for i, v in source:iterate() do
        skipping = skipping and predicate(v, i)
        if not skipping then
          out_index = out_index + 1
          yield(out_index, v)
        end
      end
    end
  )
end

do
  local function adjust_compare_function(compare, ascending, ensure_fallthrough)
    if not compare then
      if ascending then
        return function(a, b)
          return (a < b) and -1 or (a > b) and 1 or 0
        end
      else
        return function(a, b)
          return (a > b) and -1 or (a < b) and 1 or 0
        end
      end
    else
      local provided_compare = compare

      if ensure_fallthrough then
        return function(a, b)
          local result = provided_compare(a, b)
          if type(result) == "number" then
            return result
          elseif result then
            return -1
          else
            return provided_compare(b, a) and 1 or 0
          end
        end
      else
        return function(a, b)
          local result = provided_compare(a, b)
          if type(result) == "number" then
            return result
          elseif result then
            return -1
          else
            return 1
          end
        end
      end
    end
  end

  --- Returns a new @{Sqib.Seq} that consists of the elements of this sequence sorted according to the specified
  -- options.
  --
  -- With no options specified, the call
  --
  --     local result = seq:sorted()
  --
  -- is equivalent to
  --
  --     local result = seq:sorted({
  --       by = function(v) return v end,
  --       compare = function(a, b) return (a < b) and -1 or (a > b) and 1 or 0 end,
  --       ascending = true,
  --       stable = false,
  --       })
  --
  -- Otherwise, one or more orderings can be specified, each with its own full set of parameters. If two elements are
  -- tied according to the first ordering, then the second ordering is tried and so on until the tie is broken.
  --
  --    -- Example of sorting first by one field, then another, then another
  --    -- (stable = true in any of the orderings causes the entire sort to be stable)
  --    local result = seq:sorted(
  --      { by = function(v) return v.primary_field end, stable = true },
  --      { by = function(v) return v.secondary_field end, ascending = false },
  --      { by = function(v) return v.tertiary_field end, compare = some_compare_function }
  --      )
  --
  -- If all comparisons tie for two elements and `stable` is true for any of the orderings, then the element that
  -- occurred earlier in the input sequence will appear earlier in the output as well. If all comparisons tie for two
  -- elements and `stable` is *not* true for any of the orderings, the elements may appear in either order.
  --
  -- The sort operation itself is deferred and occurs at the beginning of each new iteration. All elements of this
  -- sequence are iterated at once, copied internally, and sorted, then this sorted copy is iterated.
  --
  -- @param ... Ordering specifications to be applied in order while comparing elements; each parameter is a table that
  -- may define any of the following:
  --
  -- * `by`: A function `(v)` that returns a value that will be the subject of the sort. If omitted, the sort will be
  -- performed on the value itself.
  -- * `compare`: A ternary compare function `(a, b)` that returns a negative number if `a` comes before `b`, a positive
  -- number if `a` comes after `b`, or 0 if `a` and `b` are tied. As a backward compatibility measure, if this method
  -- returns a non-number value, such as `true` or `false`, it will be treated as an ordinary Lua comparer (returns
  -- truthy if `a` comes before `b` or falsy otherwise), but if `stable` is set to true or if multiple orderings are
  -- specified, then the comparer may need to be called twice (once in each order) to determine whether two elements are
  -- tied. If omitted, the comparison is equivalent to the expression `(a < b) and -1 or (a > b) and 1 or 0`.
  -- * `ascending`: If true, the elements are arranged in ascending order. If false, the elements are arranged in
  -- descending order. If omitted, defaults to true.
  -- * `stable`: If true, the sort is stable; that is, any two elements that are tied will be sorted in the same order
  -- in which they appear in the input. If false, the sort is not guaranteed to be stable. If omitted, defaults to
  -- false. If multiple orderings are specified and at least one specifies `stable` as true, the entire result will be
  -- stable.
  -- @return A @{Sqib.Seq} representing a copy of this sequence whose elements have been sorted as specified.
  function Sqib.Seq:sorted(...)
    local selectors = {}
    local compares = {}
    local number_of_orderings = select("#", ...)

    do
      local orderings = {...}

      if number_of_orderings == 0 then
        number_of_orderings = 1
        orderings = {{}}
      end

      local stable = false

      for i = 1, number_of_orderings do
        if orderings[i].stable then
          stable = true
          break
        end
      end

      local ensure_fallthrough = stable or (number_of_orderings > 1)

      for i = 1, number_of_orderings do
        local ordering = orderings[i]
        local by = ordering.by
        local compare = ordering.compare
        local ascending = ordering.ascending

        if not by then
          by = function(v)
            return v
          end
        end
        if ascending == nil then
          ascending = true
        end
        ascending = ascending and true or false

        compare = adjust_compare_function(compare, ascending, ensure_fallthrough)

        selectors[i] = by
        compares[i] = compare
      end

      if stable then
        number_of_orderings = number_of_orderings + 1
        selectors[number_of_orderings] = function(_, i)
          return i
        end
        compares[number_of_orderings] = function(a, b)
          return (a < b) and -1 or (a > b) and 1 or 0
        end
      end
    end

    local source = self

    local function copy_sort_iterate()
      local rows = {}
      local n = 0
      do
        for _, v in source:iterate() do
          n = n + 1
          local row = {i = n, v = v}
          rows[n] = row
        end

        table.sort(
          rows,
          function(a, b)
            for i = 1, number_of_orderings do
              local selector = selectors[i]
              local compare = compares[i]

              local ak = ntaddselected(a, i, selector, a.v, a.i)
              local bk = ntaddselected(b, i, selector, b.v, b.i)

              local result = compare(ak, bk)
              if result ~= 0 then
                return result < 0
              end
            end
            return false
          end
        )

        for i = 1, n do
          rows[i] = rows[i].v
        end
      end

      return iterator_from_vanishing_array(rows, n)
    end

    return Sqib.Seq:new {iterate = copy_sort_iterate}
  end
end

--- Passes a specified number of elements, then ends the sequence.
-- @param count A number of elements to take. If this is zero or less, the result is empty. If this is the length of the
-- sequence or greater, the result is the entire sequence.
-- @return A @{Sqib.Seq} consisting of the first `count` elements of this sequence.
function Sqib.Seq:take(count)
  local source = self
  count = math.floor(count)

  if count <= 0 then
    return Sqib.empty()
  end

  return seq_from_indexed_yielder(
    function()
      local out_index = 0

      for _, v in source:iterate() do
        out_index = out_index + 1
        if out_index <= count then
          yield(out_index, v)
        end
        if out_index >= count then
          break
        end
      end
    end
  )
end

--- Passes all elements while a predicate is satisfied, then ends the sequence.
--
-- @param predicate A function `(v, i)` to test elements. Elements are passed until the first element for which this
-- returns `false`; the remaining elements are ignored.
-- @return A @{Sqib.Seq} consisting of all elements of this sequence before, but not including, the first element for
-- which the predicate returns false.
function Sqib.Seq:take_while(predicate)
  local source = self

  return seq_from_indexed_yielder(
    function()
      local out_index = 0

      for i, v in source:iterate() do
        if not predicate(v, i) then
          break
        end
        out_index = out_index + 1
        yield(out_index, v)
      end
    end
  )
end

--- Returns a new @{Sqib.Seq} that repeats this entire sequence a specified number of times.
--
-- Note that a new iteration of this sequence is started for every repetition. This may include reevaluating sequence
-- contents, filters, mappings, orderings, and so forth each time. If this isn't what you intended, use e.g. `force` to
-- fully evaluate the sequence once before using this method.
--
-- @param count The number of times to repeat this sequence.
-- @return A new @{Sqib.Seq} consisting of the elements of this sequence repeated `count` times.
function Sqib.Seq:times(count)
  count = math.floor(count)
  if count <= 0 then
    return Sqib.empty()
  end

  local source = self

  return seq_from_indexed_yielder(
    function()
      local out_index = 0

      for _ = 1, count do
        for _, v in source:iterate() do
          out_index = out_index + 1
          yield(out_index, v)
        end
      end
    end
  )
end

--- Copies this sequence into a new array.
--
-- @param[opt=false] include_length If true, this method returns the new array *and* the number of elements; otherwise,
-- this method returns only the array.
-- @return `a, n`, if `include_length`, or `a`, otherwise, where `a` is the new array and `n` is the number of elements
-- copied.
function Sqib.Seq:to_array(include_length)
  local copy = {}
  local n = self:copy_into_array(copy)

  if include_length then
    return copy, n
  else
    return copy
  end
end

--- Creates a new dictionary-style table using the provided selectors to determine the keys and values.
--
-- @param[opt] key_selector Function `(v, i)` that selects the key for an item. If omitted, the value is selected.
-- @param[opt] value_selector Function `(v, i)` that selects the value for an item. If omitted, the value is selected.
-- @return The newly created table.
-- @raise When any key appears more than once.
-- @see Sqib.Seq:pairs_to_hash
function Sqib.Seq:to_hash(key_selector, value_selector)
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

  for i, v in self:iterate() do
    local key = key_selector(v, i)
    if seen[key] then
      error("Key '" .. key .. "' encountered more than once")
    end
    seen[key] = true
    hash[key] = value_selector(v, i)
  end

  return hash
end

--- Returns this @{Sqib.Seq} object.
--
-- A method named `to_sqib_seq` on any object is assumed (e.g. by `from`) to return a Sqib sequence equivalent to the
-- object.
--
-- The `to_sqib_seq` method of @{Sqib.Seq} is specified to always return the implied `self` parameter. This should not
-- be overridden by derived types of @{Sqib.Seq}.
--
-- @return `self` (the object on which this method was called).
-- @see is_sqib_seq
-- @see Sqib.from
function Sqib.Seq:to_sqib_seq()
  return self
end

--- Filters this sequence to distinct elements by including only the first element having a selected key.
--
-- This implementation is table-based; a table is used to keep track of the keys of already seen items.
--
-- Any two elements are considered distinct if their keys do not refer to the same item when used to index a table; that
-- is, for `a` and `b`, for some table `seen`, `seen[key_selector(a)]` and `seen[key_selector(b)]` don't refer to the
-- same item.
--
-- A special case is implemented so that `nil` can be used as a key.
--
-- @param[opt] key_selector A function `(v, i)` that selects a key by which to determine uniqueness. If this is omitted,
-- the key selector returns the value itself as a key.
-- @return A @{Sqib.Seq} consisting of each element of this sequence for which the selected key has not already
-- appeared.
function Sqib.Seq:unique(key_selector)
  if key_selector == nil then
    key_selector = passthrough
  end

  local source = self

  return seq_from_indexed_yielder(
    function()
      local seen = {}
      local out_index = 0

      for i, v in source:iterate() do
        local key = key_selector(v, i)
        if ntadd(seen, key, true) then
          out_index = out_index + 1
          yield(out_index, v)
        end
      end
    end
  )
end

do
  -- Unpacks a partial block 1 element at a time.
  local function process_1(b, i, n)
    if n - (i - 1) >= 1 then
      return b[i], process_1(b, i + 1, n)
    end
  end

  -- Unpacks a partial block 8 elements at a time.
  local function process_8(b, i, n)
    if n - (i - 1) >= 8 then
      return b[i], b[i + 1], b[i + 2], b[i + 3], b[i + 4], b[i + 5], b[i + 6], b[i + 7], process_8(b, i + 8, n)
    else
      return process_1(b, i, n)
    end
  end

  -- Unpacks a full block of 64 elements.
  local function process_64(packed_blocks_iterator)
    local has, b = packed_blocks_iterator()
    if has == nil then
      return
    elseif b.n == 64 then
      -- Apologies for any ocular hemorrhage caused by the formatting here. It truly is worse without the breaks.
      return b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15], b[
        16 --[[intentional break here]]
      ], b[17], b[18], b[19], b[20], b[21], b[22], b[23], b[24], b[25], b[26], b[27], b[28], b[29], b[30], b[31], b[
        32 --[[intentional break here]]
      ], b[33], b[34], b[35], b[36], b[37], b[38], b[39], b[40], b[41], b[42], b[43], b[44], b[45], b[46], b[47], b[
        48 --[[intentional break here]]
      ], b[49], b[50], b[51], b[52], b[53], b[54], b[55], b[56], b[57], b[58], b[59], b[60], b[61], b[62], b[63], b[
        64 --[[intentional break here]]
      ], process_64(packed_blocks_iterator)
    else
      return process_8(b, 1, b.n)
    end
  end

  local function unpack_via_packed_blocks(source)
    local packed_blocks_iterator = source:batch(64):iterate()
    return process_64(packed_blocks_iterator)
  end

  --- Returns this entire sequence as a return value list.
  --
  -- Similarly to the built-in `unpack`, this method produces the values from a sequence in a form suitable for multiple
  -- assignment or for appending to an array or parameter list.
  --
  --    local seq = Sqib.over(10, 20, 30)
  --    local q, r, s = seq:unpack()  -- like q = 10, r = 20, s = 30
  --    local a = {seq:unpack()}      -- like a = {10, 20, 30}
  --    local a2 = {0, seq:unpack()}  -- like a = {0, 10, 20, 30}
  --    print("values", seq:unpack()) -- like print("values", 10, 20, 30)
  --
  -- [Implementation detail: This implementation may cause a stack overflow condition for a very large number of
  -- elements (as determined during testing, a little over a million; may vary by target environment). The
  -- implementation of this method relies on a recursive function call that Lua 5.1 seems unable to tail-call optimize.
  -- The depth of the call stack is directly proportional to the number of elements.]
  --
  -- @return All elements of this sequence in order.
  function Sqib.Seq:unpack()
    return unpack_via_packed_blocks(self)
  end
end

return Sqib
