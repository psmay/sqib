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
-- @release 0.1.0-ab

local Sqib = {
  _VERSION = "0.1.0-ab"
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
  return ev == _NT_NIL_SURROGATE and nil or ev
end

-- unescape a nil-escaped value, returning true, value if defined or false, nil if undefined
local function _nt_xunescape(ev)
  local defined = ev ~= nil
  local value = defined and _nt_unescape(ev) or nil
  return defined, value
end

-- get a value from an nt, or nil if not defined
local function ntget(t, k)
  return _nt_unescape(t[_nt_escape(k)])
end

-- set a value on an nt
local function ntset(t, k, v)
  t[_nt_escape(k)] = _nt_escape(v)
end

-- remove a value on an nt
local function ntremove(t, k)
  t[_nt_escape(k)] = nil
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

-- get a value from an nt, returning true, value if exists or false, nil if not exists
local function ntxget(t, k)
  return _nt_xunescape(t[_nt_escape(k)])
end

-- set a value on an nt, returning true, previous_value if previously set or false, nil if not previously set
local function ntxset(t, k, v)
  local ek = _nt_escape(k)
  local ev = t[ek]
  t[ek] = _nt_escape(v)
  return _nt_xunescape(ev)
end

-- removes a value on an nt, returning true, previous_value if previously set or false, nil if not previously set
local function ntxremove(t, k)
  local ek = _nt_escape(k)
  local ev = t[ek]
  t[ek] = nil
  return _nt_xunescape(ev)
end

-- iterates over the pairs of an nt, to be used in the idiom
--  for i, kv in ntxpairs(nt) do
--    local k, v = unpack(kv)
--    ...
--  end
local function ntxpairs(t)
  local out_index = 0
  local iter, inv, ctl = pairs(t)
  return function()
    local ek, ev = iter(inv, ctl)
    if ek ~= nil then
      out_index = out_index + 1
      ctl = ek
      return out_index, {_nt_unescape(ek), _nt_unescape(ev)}
    end
  end
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

local function iterator_from_yielder(yielder)
  -- Could probably be done with coroutine.wrap, but I got this to work first.
  local co = coroutine.create(yielder)
  return function()
    local code, index, value = coroutine.resume(co)
    return index, value
  end
end

-- Iterator over a temporary array, where each element is deleted as it is read.
local function iterator_from_vanishing_array(a, n)
  if type(n) ~= "number" then
    error("Iterator over vanishing array failed; n is " .. type(n) .. "; expected number")
  end
  return iterator_from_yielder(
    function()
      for i = 1, n do
        local v = a[i]
        a[i] = nil
        yield(i, v)
      end
    end
  )
end

local function seq_from_yielder(yielder)
  return Sqib.Seq:new {
    iterate = function()
      return iterator_from_yielder(yielder)
    end
  }
end

-- Sqib:from(v) packaged as a selector.
local function selector_seq_from(v, i)
  return Sqib:from(v)
end

-- Internal implementation: Given `source`, a `Sqib.Seq` of `Sqib.Seq`, returns a `Sqib.Seq` that is the concatenation
-- of the sequences. No selection or conversion is applied.
local function flatten(source)
  return seq_from_yielder(
    function()
      local out_index = 0

      for si, sv in source:iterate() do
        for i, v in sv:iterate() do
          out_index = out_index + 1
          yield(out_index, v)
        end
      end
    end
  )
end

-- Guesses the best way to convert `x` to a `Sqib.Seq`, returning `nil` if it gives up.
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
    elseif type(x.n) == "number" then
      return Sqib:from_packed(x)
    else
      return Sqib:from_array(x)
    end
  elseif type_x == "function" then
    return Sqib:from_iterate(x)
  else
    return nil
  end
end

-- Converts the first `n` elements of `a` to `Sqib.Seq` using `try_seq_from()`, raising an error if any element fails to
-- convert. Returns the concatenation of the results as a `Sqib.Seq`.
local function seq_from_all(a, n)
  if n <= 0 then
    return Sqib:empty()
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
    return Sqib:empty()
  elseif n == 1 then
    return sequences[1]
  else
    return flatten(Sqib:from_array(sequences, n))
  end
end

local function seq_from_pairs(t, result_selector)
  if result_selector == nil then
    result_selector = function(k, v)
      return {k, v}
    end
  end

  return seq_from_yielder(
    function()
      local out_index = 0
      for k, v in pairs(t) do
        out_index = out_index + 1
        yield(out_index, result_selector(k, v))
      end
    end
  )
end

local function seq_from_array(a, n)
  if n ~= nil then
    if type(n) ~= "number" then
      error("Creating sequence from array failed; n is " .. type(n) .. "; expected number or nil")
    end
    return seq_from_yielder(
      function()
        for i = 1, n do
          yield(i, a[i])
        end
      end
    )
  else
    return seq_from_yielder(
      function()
        local count = #a
        for i = 1, count do
          yield(i, a[i])
        end
      end
    )
  end
end

local function seq_from_packed(t)
  return seq_from_yielder(
    function()
      local n = t.n
      if type(n) ~= "number" then
        error("Iterator over packed list failed; n is " .. type(n) .. "; expected number")
      end
      for i = 1, n do
        yield(i, t[i])
      end
    end
  )
end

--- Static methods for creating Sqib sequences.
--
-- @type Sqib

do
  -- This is lazy so that it can appear before Sqib.Seq:new() is defined.
  local get_empty_seq = function()
    local EmptySeq = Sqib.Seq:new()

    function EmptySeq:iterate()
      return noop
    end

    function EmptySeq:count()
      return 0
    end

    get_empty_seq = function()
      return EmptySeq:new()
    end

    return get_empty_seq()
  end

  --- Returns a new `Sqib.Seq` containing zero elements.
  --
  -- @return A new, empty `Sqib.Seq`.
  function Sqib:empty()
    return get_empty_seq()
  end
end

--- Produces a `Sqib.Seq` by guessing the appropriate conversion for `value`.
--
--  - If `value` is a table,
--     - If `value.is_sqib_seq` exists as a function and `value:is_sqib_seq()` returns true, `value` is used.
--     - If `value.to_sqib_seq` exists as a function, the result of `value:to_sqib_seq()` is used.
--       - This handles the case of a value already being a `Sqib.Seq`; `Sqib.Seq:to_sqib_seq()` is defined to return
--         `self`.
--       - If the value `seq` returned by `value:to_sqib_seq()` is not a table, or `seq.is_sqib_seq` is not a function,
--         or `seq:is_sqib_seq()` does not return true, an error is raised.
--     - Otherwise, if `value.n` exists as a number, the result of `Sqib:from_packed(value)` is used.
--     - Otherwise, the result of `Sqib:from_array(value)` is used.
--  - If `value` is a function, the result of `Sqib:from_iterate(value)` is used.
--  - Otherwise, an error is raised.
--
-- @param value A sequence-like value to be converted to a sequence.
-- @return A `Sqib.Seq` obtained by automatically converting `value`.
-- @raise * When `value` has no automatic conversion to a sequence.
-- * When `value:to_sqib_seq()`, if found, returns a value that does not appear to be a sequence (i.e., does not pass
--   the `is_sqib_seq()` test).
function Sqib:from(value)
  local s = try_seq_from(value)
  if s == nil then
    error("Value has no automatic conversion to a sequence")
  end
  return s
end

--- Returns a `Sqib.Seq` based on the key-value pairs of a table.
--
-- @param t A table whose key-value pairs to traverse.
-- @param[opt] result_selector A function `(k, v)` that selects the output element based on each key-value pair. If
-- omitted, the selector produces a two-element array `{k, v}` containing the key and the value.
-- @return A new `Sqib.Seq` representing the key-value pairs of `t`, in no particular order.
function Sqib:from_pairs(t, result_selector)
  return seq_from_pairs(t, result_selector)
end

--- Returns a `Sqib.Seq` based on the keys of a table.
--
-- @param t A table whose keys to traverse.
-- @return A new `Sqib.Seq` representing the keys of `t`, in no particular order.
function Sqib:from_keys(t)
  return Sqib:from_pairs(
    t,
    function(k)
      return k
    end
  )
end

--- Returns a `Sqib.Seq` based on the values of a table.
--
-- @param t A table whose values to traverse.
-- @return A new `Sqib.Seq` representing the values of `t`, in no particular order.
function Sqib:from_values(t)
  return Sqib:from_pairs(
    t,
    function(_, v)
      return v
    end
  )
end

--- Produces a `Sqib.Seq` by converting each parameter to a `Sqib.Seq` (using the same rules as `Sqib:from()`) and
-- concatenating the results.
--
-- @param ... Sequence-like values to be converted to sequences and concatenated.
-- @return A `Sqib.Seq` obtained by automatically converting every parameter to a `Sqib.Seq`, then concatenating the
-- results.
-- @raise * When any parameter has no automatic conversion to a sequence.
-- * When, for any parameter `v`, `v:to_sqib_seq()` is found but returns a value that does not appear to be a sequence
--   (i.e., does not pass the `is_sqib_seq()` test).
function Sqib:from_all(...)
  local n = select("#", ...)
  return seq_from_all({...}, n)
end

--- Returns a `Sqib.Seq` based on the first `n` elements of the array `a` (or the first `#a` elements, if `n` is
-- omitted).
--
-- @param a An array on which to base the new sequence.
-- @param[opt] n The number of elements to include from `a`. If omitted, the length is recomputed from `#a` at the
-- beginning of each new iteration.
-- @return A `Sqib.Seq` consisting of the first `n` elements of `a`, or, if `n` is omitted, the first `#a` elements of
-- `a`.
function Sqib:from_array(a, n)
  return seq_from_array(a, n)
end

--- Returns a `Sqib.Seq` based on the supplied iterate function.
--
-- The function `iterate` is expected to return an iterator function and optionally stateless iterator parameters.
-- `iterate` is used in a construction similar to `for _, v in iterate() do ... end` and has a similar contract to the
-- built-in `ipairs()` or `pairs()` functions.
--
-- The iteration is expected to produce each successive element of the represented sequence by returning
--
-- * a pair `_, v`, where `_` is any non-`nil` value and `v` is the next element value, or
-- * `nil`, signaling the end of the sequence.
--
-- The index value produced by the iterator need not be in any particular order; the requirement is only that the index
-- value be non-`nil` when a value is being returned or `nil` once the sequence is exhausted. The `Sqib.Seq` returned
-- from this method discards the indexes from the iterator and provides its own indexes that comply with the contract of
-- `Sqib.Seq:iterate()`.
--
-- @param iterate A function which returns an iterator function.
-- @return A new `Sqib.Seq` based on the abstract sequence traversed by `iterate`, with renumbered indexes.
function Sqib:from_iterate(iterate)
  return seq_from_yielder(
    function()
      local out_index = 0
      for _, v in iterate() do
        out_index = out_index + 1
        yield(out_index, v)
      end
    end
  )
end

--- Returns a `Sqib.Seq` based on the packed array `a` whose length is `a.n`.
--
-- @param t A packed list table; i.e. an array with an `n` property explicitly set to the list length.
-- @return A new `Sqib:Seq` based on the elements of `t`.
function Sqib:from_packed(t)
  return seq_from_packed(t)
end

--- Returns a `Sqib.Seq` over the supplied sequence of parameters.
--
-- @param ... Elements to be traversed by the new sequence.
-- @return A new `Sqib.Seq` based on the values of `...`.
function Sqib:over(...)
  local n = select("#", ...)
  if n == 0 then
    return Sqib:empty()
  end
  return Sqib:from_array({...}, n)
end

--- Returns a new `Sqib.Seq` over the specified range.
--
-- The sequence produced is the same sequence produced by the `for` loop
--
--     for i=start_value, limit_value, step do ... end
--
-- @param start_value The initial value of the range.
-- @param limit_value The limit for the final value of the range.
-- @param[opt=1] step The step value for iteration.
-- @return A new `Sqib.Seq` with contents based on the specified range.
function Sqib:range(start_value, limit_value, step)
  if step == nil then
    step = 1
  end

  return seq_from_yielder(
    function()
      local out_index = 0

      for i = start_value, limit_value, step do
        out_index = out_index + 1
        yield(out_index, i)
      end
    end
  )
end

--- Returns a new `Sqib.Seq` that repeats a specified value a specified number of times.
--
-- @param value The element value to be repeated.
-- @param count The number of times to repeat `value`.
-- @return A new `Sqib.Seq` consisting of `value` repeated `count` times.
function Sqib:times(value, count)
  count = math.floor(count)
  if count <= 0 then
    return Sqib:empty()
  else
    return seq_from_yielder(
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
-- Derived classes must implement `Sqib.Seq:iterate`. If a derived class can determine its own size in less-than-linear
-- time, it should also override `Sqib.Seq:count`.
--
-- @type Sqib.Seq

Sqib.Seq = {}

--- The constructor for `Sqib.Seq`, not meant to be instantiated directly.
--
-- This method is provided to allow subclasses. The implementation does nothing beyond creating the object and setting
-- the type's index and the instance's metatable.
--
-- See the methods of `Sqib` (for example, `Sqib:from()`) for simple ways to create `Sqib.Seq` objects from actual data.
--
-- @param[opt={}] o A table to convert into this type.
-- @return `o`, having been converted to this type.
function Sqib.Seq:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

--- Counts the number of elements, or the number of elements that satisfy a predicate, in this `Sqib.Seq`.
--
-- @param[opt] predicate A function `(v, i)` that returns true if the current element satisfies a condition or false
-- otherwise. If omitted, all elements are counted.
-- @return The total number of elements (if `predicate` is omitted) or the number of elements that satisfy `predicate`
-- (if `predicate` is supplied) in this `Sqib.Seq`.
function Sqib.Seq:count(predicate)
  local n = 0

  if predicate == nil then
    for i, v in self:iterate() do
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
-- @return A new `Sqib.Seq` consisting of the elements of this `Sqib.Seq` that satisfy `predicate`.
function Sqib.Seq:filter(predicate)
  local source = self

  return seq_from_yielder(
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
-- `Sqib.Seq` using `Sqib:from()`, which allows the operation to flatten certain other non-`Sqib.Seq` sequences. Set to
-- `false` if the selector always produces a `Sqib.Seq` and doesn't need the additional conversion.
-- @return A new `Sqib.Seq` consisting of the concatenated elements of the sequences returned by `selector` as applied
-- to each element from this `Sqib.Seq`.
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
-- This method iterates this sequence completely, making an immutable copy, and returns a `Sqib.Seq` based on the copy.
--
-- The main effects of using the returned `Sqib.Seq` in place of the original sequence are:
--
-- * The resulting sequence itself doesn't need to perform any non-trivial computations. Any (potentially intensive)
--   computation specified before the force only happens once.
-- * The resulting sequence will not vary between iterations, even if
--   * this source sequence is mutable (such as an array passed to `Sqib:from()`, if anything other than the sequence
--     still has a reference to it)
--   * this source sequence is based on computations which use variables that are themselves mutable
-- * The resulting sequence generally occupies more memory.
--
-- The effect of conversions such as `Sqib.Seq:to_array()` or `Sqib.Seq:pack()` is similar, except that those methods
-- do not directly produce a `Sqib.Seq` and this method does not produce an object which can be accessed as a table.
--
-- @return A new `Sqib.Seq` based on an immutable copy of the values from an immediate, full iteration of this
-- `Sqib.Seq`.
function Sqib.Seq:force()
  local a, n = self:to_array(true)
  return Sqib:from_array(a, n)
end

--- Returns whether this object should be treated as `Sqib.Seq`.
--
-- A function named `is_sqib_seq` on any object is assumed (e.g. by `Sqib:from()`) to return `true` if the object is a
-- `Sqib.Seq` (or close enough to one that it can be treated as one). This method exists for the purpose of identifying
-- an object as a `Sqib.Seq` in absence of any reliable way to do so in Lua.
--
-- `Sqib:Seq:is_sqib_seq()` is specifically defined to return `true`.
--
-- This should not be overridden by derived types of `Sqib.Seq`.
--
-- @return `true`.
-- @see Sqib.Seq:to_sqib_seq
function Sqib.Seq:is_sqib_seq()
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
-- @return A closure-based iterator over this sequence.
function Sqib.Seq:iterate()
  error("iterate() method is not implemented")
end

--- Maps each element of this sequence by applying a selector.
--
-- @param selector A function `(v, i)` to apply to each element in the sequence.
-- @return A new `Sqib.Seq` consisting of the elements of this `Sqib.Seq` with `selector` applied to each element.
function Sqib.Seq:map(selector)
  local source = self

  return seq_from_yielder(
    function()
      for i, v in source:iterate() do
        yield(i, selector(v, i))
      end
    end
  )
end

do
  local function reverse_in_place(a, n)
    local forward_i = 1
    local reverse_i = n

    while forward_i < reverse_i do
      local tmp = a[forward_i]
      a[forward_i] = a[reverse_i]
      a[reverse_i] = tmp

      forward_i = forward_i + 1
      reverse_i = reverse_i - 1
    end
  end

  --- Returns a new `Sqib.Seq` that consists of the elements of this sequence in reverse order.
  --
  -- The reverse operation itself is deferred and occurs whenever the returned `Sqib.Seq` is actually iterated. When an
  -- iterator is retrieved, the entire contents of the source sequence are copied into an internal table. This table is
  -- reversed in place, then the resulting element values are iterated.
  --
  -- @return A `Sqib.Seq` representing a copy of this `Sqib.Seq` whose elements have been reversed.
  function Sqib.Seq:reversed()
    local source = self

    return Sqib.Seq:new {
      iterate = function()
        local a, n = source:to_array(true)
        reverse_in_place(a, n)
        return iterator_from_vanishing_array(a, n)
      end
    }
  end
end

--- Skips a specified number of elements, then passes through the remainder.
--
-- @param count A number of elements to skip. If this is zero or less, the result is the entire sequence. If this is the
-- length of the sequence or greater, the result is empty.
-- @return A `Sqib.Seq` consisting of the elements of this `Sqib.Seq` after the first `count` elements have been
-- skipped.
function Sqib.Seq:skip(count)
  local source = self
  count = math.floor(count)

  if count <= 0 then
    return source
  end

  return seq_from_yielder(
    function()
      local out_index = -count

      for i, v in source:iterate() do
        out_index = out_index + 1
        if out_index >= 1 then
          yield(out_index, v)
        end
      end
    end
  )
end

--- Skips all elements while a predicate is satisfied, then passes through the remainder.
--
-- @param predicate A function `(v, i)` to test elements. Elements are skipped until the first element for which this
-- returns false; the remaining elements are passed through untested.
-- @return A `Sqib.Seq` consisting of all elements of this `Sqib.Seq` including and after the first element for which
-- the predicate returns false.
function Sqib.Seq:skip_while(predicate)
  local source = self

  return seq_from_yielder(
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

--- Passes a specified number of elements, then ends the sequence.
-- @param count A number of elements to take. If this is zero or less, the result is empty. If this is the length of the
-- sequence or greater, the result is the entire sequence.
-- @return A `Sqib.Seq` consisting of the first `count` elements of this `Sqib.Seq`.
function Sqib.Seq:take(count)
  local source = self
  count = math.floor(count)

  if count <= 0 then
    return Sqib:empty()
  end

  return seq_from_yielder(
    function()
      local out_index = 0

      for i, v in source:iterate() do
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
-- @return A `Sqib.Seq` consisting of all elements of this `Sqib.Seq` before, but not including, the first element for
-- which the predicate returns false.
function Sqib.Seq:take_while(predicate)
  local source = self

  return seq_from_yielder(
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

  --- Returns a new `Sqib.Seq` that consists of the elements of this sequence sorted according to the specified options.
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
  --     local result = seq:sorted(
  --       { by = function(v) return v.primary_field end, stable = true },
  --       { by = function(v) return v.secondary_field end, ascending = false },
  --       { by = function(v) return v.tertiary_field end, compare = some_compare_function }
  --       )
  --
  -- If all comparisons tie for two elements and `stable` is specified for any of the orderings, then the element that
  -- occurred earlier in the input sequence will appear earlier in the output as well. If all comparisons tie for two
  -- elements and `stable` is *not* specified for any of the orderings, the elements may appear in either order.
  --
  -- The sort operation itself is deferred and occurs whenever the returned `Sqib.Seq` is actually iterated. When an
  -- iterator is retrieved, the entire contents of the source sequence are copied into an internal table, possibly with
  -- some additional information to aid processing. This table is sorted in place, then the resulting element values are
  -- iterated.
  --
  -- @param ... Parameters for the sorting process:
  --
  -- * `by`: A function `(v)` that returns a value that will be the subject of the sort. If omitted, the sort will be
  -- performed on the value itself.
  -- * `compare`: A ternary compare function `(a, b)` that returns a negative number if `a` comes before `b`, a positive
  -- number if `a` comes after `b`, or 0 if `a` and `b` are tied. As a backward compatibility measure, if this method
  -- returns a non-number value, it will be treated as an ordinary Lua comparer (returns truthy if `a` comes before `b`
  -- or falsy otherwise), but if `stable` is set to true or if multiple orderings are specified, then the comparer may
  -- need to be called twice (once in each order) to determine whether two elements are tied. If omitted, the comparison
  -- is equivalent to the expression `(a < b) and -1 or (a > b) and 1 or 0`.
  -- * `ascending`: If true, the elements are arranged in ascending order. If false, the elements are arranged in
  -- descending order. If omitted, defaults to true.
  -- * `stable`: If true, the sort is stable; that is, any two elements that are tied will be sorted in the same order
  -- in which they appear in the input. If false, the sort is not guaranteed to be stable. If omitted, defaults to
  -- false. If multiple orderings are specified and at least one specifies `stable` as true, the entire result will be
  -- stable.
  -- @return A `Sqib.Seq` representing a copy of this `Sqib.Seq` whose elements have been sorted as specified.
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
        selectors[number_of_orderings] = function(v, i)
          return i
        end
        compares[number_of_orderings] = function(a, b)
          return (a < b) and -1 or (a > b) and 1 or 0
        end
      end
    end

    local source = self

    local function copy_sort_iterate()
      local elements = {}
      local n = 0
      do
        local rows = {}

        for i, v in source:iterate() do
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
          elements[i] = rows[i].v
        end
      end

      local i = 0

      return iterator_from_vanishing_array(elements, n)
    end

    return Sqib.Seq:new {iterate = copy_sort_iterate}
  end
end

--- Returns a new `Sqib.Seq` that repeats this entire sequence a specified number of times.
--
-- Note that a new iteration of this sequence is started for every repetition. This may include reevaluating sequence
-- contents, filters, mappings, orderings, and so forth each time. If this isn't what you intended, use e.g.
-- `Sqib.Seq:force()` to fully evaluate the sequence once before using this method.
--
-- @param count The number of times to repeat this sequence.
-- @return A new `Sqib.Seq` consisting of the elements of this sequence repeated `count` times.
function Sqib.Seq:times(count)
  count = math.floor(count)
  if count <= 0 then
    return Sqib:empty()
  end

  local source = self

  return seq_from_yielder(
    function()
      local out_index = 0

      for i = 1, count do
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
  local q = self:iterate()

  local i = 0
  for _, v in q do
    i = i + 1
    copy[i] = v
  end

  if include_length then
    return copy, i
  else
    return copy
  end
end

--- Copies this sequence into a new packed list.
--
-- @return A new table containing the elements of this sequence, with a property `n` containing the length of the list.
function Sqib.Seq:pack()
  local copy, n = self:to_array(true)
  copy.n = n
  return copy
end

--- Creates a new dictionary-style table using the provided selectors to determine the keys and values.
--
-- @param key_selector Function `(v, i)` that selects the key for an item. If omitted, the value is selected.
-- @param value_selector Function `(v, i)` that selects the value for an item. If omitted, the value is selected.
-- @return The newly created table.
-- @raise When any key appears more than once.
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

--- Returns this `Sqib.Seq` object.
--
-- A method named `to_sqib_seq` on any object is assumed (e.g. by `Sqib:from()`) to return a Sqib sequence equivalent to
-- the object.
--
-- `Sqib.Seq:to_sqib_seq()` is specifically defined to return `self`.
--
-- This should not be overridden by derived types of `Sqib.Seq`.
--
-- @return `self`.
-- @see Sqib.Seq:is_sqib_seq
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
-- @return A `Sqib.Seq` consisting of each element of this `Sqib.Seq` for which the selected key has not already
-- appeared.
function Sqib.Seq:unique(key_selector)
  if key_selector == nil then
    key_selector = passthrough
  end

  local source = self

  return seq_from_yielder(
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

return Sqib

