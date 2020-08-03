-- busted --lua=lua5.1 tests/main.lua

local Sqib = require "Sqib"

--
-- Test setup
--

-- Mimics ipairs(), but keeps the null values. If the length parameter `n` is not provided, `#a` is used.
local nillable_ipairs
do
  local function iter(wrapper, i)
    if i < wrapper.n then
      i = i + 1
      return i, wrapper.a[i]
    end
  end

  nillable_ipairs = function(a, n)
    if n == nil then
      n = #a
    end
    local wrapper = {a = a, n = n}
    return iter, wrapper, 0
  end
end

-- Returns a verbose form of the result of the iteration.
local function dump_iter(iterator_factory)
  local out_index = 0
  local result = {}

  for i, v in iterator_factory() do
    out_index = out_index + 1
    if (out_index > 1000000) then
      error("Iterator not intended to go this long")
    end
    result[out_index] = {i = i, v = v}
  end

  result.n = out_index

  return result
end

local function dump_sqib(seq)
  return dump_iter(
    function()
      return seq:iterate()
    end
  )
end

local dump_params
local dump_array
local dump_packed
do
  local function dump_from_table(a, n)
    local out_index = 0
    local result = {}

    for i = 1, n do
      out_index = i
      result[i] = {i = i, v = a[i]}
    end

    result.n = out_index

    return result
  end

  dump_params = function(...)
    local n = select("#", ...)
    local a = {...}
    return dump_from_table(a, n)
  end

  dump_array = function(a, n)
    if n == nil then
      n = #a
    end
    return dump_from_table(a, n)
  end

  dump_packed = function(p)
    return dump_from_table(p, p.n)
  end
end

local function deepish_equal(a, b)
  if a == b then
    return true
  elseif type(a) == "table" and type(b) == "table" then
    local seen = {}

    for k, v in pairs(a) do
      local bv = b[k]
      if not deepish_equal(v, bv) then
        return false
      else
        seen[k] = true
      end
    end

    for k, v in pairs(b) do
      if not seen[k] then
        return false
      end
    end

    return true
  end
  return false
end

-- The operation provided here is a full disjunction on not two sets but two multisets; multiplicities are accounted
-- for. For example, if `a` contains 1, 1, 1, 2, 2 and `b` contains 1, 1, 2, 2, 2, then `both` will contain 1, 1, 2, 2, `a_only`
-- will contain 1, and `b_only` will contain 2.
--
-- The output sequencing is deterministic.
--
-- If `keep_both_sides` is true, each item in the `both` sequence will contain the values from both sides as a list `{
-- av, bv }`. If false, each item will contain the `a` side only.
local function dump_full_disjunction(dump_a, dump_b, join_on, keep_both_sides)
  if join_on == nil then
    join_on = deepish_equal
  end

  -- This algorithm is not suitable for production code, but this is a test.

  local results = {}

  local function remove_row(rows, v)
    for i = 1, #rows do
      if join_on(rows[i].v, v) then
        table.remove(rows, i)
        return true
      end
    end
    return false
  end

  for i = 1, dump_a.n do
    local av = dump_a[i].v
    results[i] = {a_exists = true, a_value = av, b_exists = false}
  end

  for i = 1, dump_b.n do
    local bv = dump_b[i].v

    local row_to_use

    for j = 1, #results do
      local row = results[j]
      if row.a_exists and not row.b_exists and join_on(row.a_value, bv) then
        row_to_use = row
        break
      end
    end

    if row_to_use == nil then
      row_to_use = {a_exists = false}
      results[#results + 1] = row_to_use
    end

    row_to_use.b_exists = true
    row_to_use.b_value = bv
  end

  local a_only = {}
  local b_only = {}
  local both = {}

  for i = 1, #results do
    local row = results[i]
    if row.a_exists then
      if row.b_exists then
        local bothi = #both + 1
        if keep_both_sides then
          both[bothi] = {i = bothi, v = {row.a_value, row.b_value}}
        else
          both[bothi] = {i = bothi, v = row.a_value}
        end
      else
        local ai = #a_only + 1
        a_only[ai] = {i = ai, v = row.a_value}
      end
    else
      local bi = #b_only + 1
      b_only[bi] = {i = bi, v = row.b_value}
    end
  end

  a_only.n = #a_only
  b_only.n = #b_only
  both.n = #both

  return {
    a_only = a_only,
    b_only = b_only,
    both = both
  }
end

--
-- Test function sanity checks
--

-- Test this first; other tests define expected in terms of it.
describe(
  "Test function dump_params()",
  function()
    it(
      "returns the expected result for an empty sequence",
      function()
        local dump = dump_params()
        assert.same({n = 0}, dump)
      end
    )
    it(
      "returns the expected result for a sequence of non-nils",
      function()
        local dump = dump_params(2, 4, 6)
        assert.same({n = 3, {i = 1, v = 2}, {i = 2, v = 4}, {i = 3, v = 6}}, dump)
      end
    )
    it(
      "returns the expected result for a sequence with a leading nil",
      function()
        local dump = dump_params(nil, 4, 6)
        assert.same({n = 3, {i = 1, v = nil}, {i = 2, v = 4}, {i = 3, v = 6}}, dump)
      end
    )
    it(
      "returns the expected result for a sequence with an inner nil",
      function()
        local dump = dump_params(2, nil, 6)
        assert.same({n = 3, {i = 1, v = 2}, {i = 2, v = nil}, {i = 3, v = 6}}, dump)
      end
    )
    it(
      "returns the expected result for a sequence with a trailing nil",
      function()
        local dump = dump_params(2, 4, nil)
        assert.same({n = 3, {i = 1, v = 2}, {i = 2, v = 4}, {i = 3, v = nil}}, dump)
      end
    )
  end
)

describe(
  "Test function dump_array() (no length parameter)",
  function()
    it(
      "is consistent with dump_params() for an empty sequence",
      function()
        local dump = dump_array({})
        assert.same(dump_params(), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence of non-nils",
      function()
        local dump = dump_array({2, 4, 6})
        assert.same(dump_params(2, 4, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with a leading nil",
      function()
        local dump = dump_array({nil, 4, 6})
        assert.same(dump_params(nil, 4, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with an inner nil",
      function()
        local dump = dump_array({2, nil, 6})
        assert.same(dump_params(2, nil, 6), dump)
      end
    )
    it(
      "omits the trailing nil of a sequence with a trailing nil",
      function()
        local dump = dump_array({2, 4, nil})
        assert.same(dump_params(2, 4), dump)
      end
    )
  end
)

describe(
  "Test function dump_array() (with length parameter)",
  function()
    it(
      "is consistent with dump_params() for an empty sequence",
      function()
        local dump = dump_array({}, 0)
        assert.same(dump_params(), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence of non-nils",
      function()
        local dump = dump_array({2, 4, 6}, 3)
        assert.same(dump_params(2, 4, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with a leading nil",
      function()
        local dump = dump_array({nil, 4, 6}, 3)
        assert.same(dump_params(nil, 4, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with an inner nil",
      function()
        local dump = dump_array({2, nil, 6}, 3)
        assert.same(dump_params(2, nil, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with a trailing nil",
      function()
        local dump = dump_array({2, 4, nil}, 3)
        assert.same(dump_params(2, 4, nil), dump)
      end
    )
  end
)

describe(
  "Test function dump_packed()",
  function()
    it(
      "is consistent with dump_params() for an empty sequence",
      function()
        local dump = dump_packed({n = 0})
        assert.same(dump_params(), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence of non-nils",
      function()
        local dump = dump_packed({n = 3, 2, 4, 6})
        assert.same(dump_params(2, 4, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with a leading nil",
      function()
        local dump = dump_packed({n = 3, nil, 4, 6})
        assert.same(dump_params(nil, 4, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with an inner nil",
      function()
        local dump = dump_packed({n = 3, 2, nil, 6})
        assert.same(dump_params(2, nil, 6), dump)
      end
    )
    it(
      "is consistent with dump_params() for a sequence with a trailing nil",
      function()
        local dump = dump_packed({n = 3, 2, 4, nil})
        assert.same(dump_params(2, 4, nil), dump)
      end
    )
  end
)

describe(
  "Test function dump_iter()",
  function()
    it(
      "with builtin ipairs(), returns the expected result for an empty sequence",
      function()
        local dump =
          dump_iter(
          function()
            return ipairs({})
          end
        )
        assert.same(dump_params(), dump)
      end
    )
    it(
      "with builtin ipairs(), returns the expected result for a sequence of non-nils",
      function()
        local dump =
          dump_iter(
          function()
            return ipairs({2, 4, 6})
          end
        )
        assert.same(dump_params(2, 4, 6), dump)
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for an empty sequence",
      function()
        local dump =
          dump_iter(
          function()
            return nillable_ipairs({})
          end
        )
        assert.same(dump_params(), dump)
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for a sequence of non-nils",
      function()
        local dump =
          dump_iter(
          function()
            return nillable_ipairs({2, 4, 6})
          end
        )
        assert.same(dump_params(2, 4, 6), dump)
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for a sequence with a leading nil",
      function()
        local dump =
          dump_iter(
          function()
            return nillable_ipairs({nil, 4, 6})
          end
        )
        assert.same(dump_params(nil, 4, 6), dump)
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for a sequence with an inner nil",
      function()
        local dump =
          dump_iter(
          function()
            return nillable_ipairs({2, nil, 6})
          end
        )
        assert.same(dump_params(2, nil, 6), dump)
      end
    )
    it(
      "with test function nillable_ipairs() (with length parameter), returns the expected result for a sequence with an trailing nil",
      function()
        local dump =
          dump_iter(
          function()
            return nillable_ipairs({2, 4, nil}, 3)
          end
        )
        assert.same(dump_params(2, 4, nil), dump)
      end
    )
  end
)

describe(
  "Test function dump_full_disjunction() (no keep_both_sides)",
  function()
    it(
      "with identical inputs, returns as expected",
      function()
        local a = dump_params(1, 1, 2, 3, 5)
        local b = dump_params(1, 1, 2, 3, 5)

        local actual = dump_full_disjunction(a, b)

        local expected = {
          a_only = dump_params(),
          b_only = dump_params(),
          both = dump_params(1, 1, 2, 3, 5)
        }

        assert.same(expected, actual)
      end
    )
    it(
      "with only a inputs, returns as expected",
      function()
        local a = dump_params(1, 1, 2, 3, 5)
        local b = dump_params()

        local actual = dump_full_disjunction(a, b)

        local expected = {
          a_only = dump_params(1, 1, 2, 3, 5),
          b_only = dump_params(),
          both = dump_params()
        }

        assert.same(expected, actual)
      end
    )
    it(
      "with only b inputs, returns as expected",
      function()
        local a = dump_params()
        local b = dump_params(1, 1, 2, 3, 5)

        local actual = dump_full_disjunction(a, b)

        local expected = {
          a_only = dump_params(),
          b_only = dump_params(1, 1, 2, 3, 5),
          both = dump_params()
        }

        assert.same(expected, actual)
      end
    )
    it(
      "with partially overlapping inputs, returns as expected",
      function()
        local a = dump_params(6, 1, 0, 2, 1, 3, 5, 2, 5, 6)
        local b = dump_params(2, 9, 3, 7, 3, 3, 6, 7, 9, 5)

        local actual = dump_full_disjunction(a, b)

        local expected = {
          a_only = dump_params(1, 0, 1, 2, 5, 6),
          b_only = dump_params(9, 7, 3, 3, 7, 9),
          both = dump_params(6, 2, 3, 5)
        }

        assert.same(expected, actual)
      end
    )
  end
)

describe(
  "Test function dump_full_disjunction() (keep_both_sides)",
  function()
    it(
      "with identical inputs, returns as expected",
      function()
        local a = dump_params(1, 1, 2, 3, 5)
        local b = dump_params(1, 1, 2, 3, 5)

        local actual = dump_full_disjunction(a, b, nil, true)

        local expected = {
          a_only = dump_params(),
          b_only = dump_params(),
          both = dump_params({1, 1}, {1, 1}, {2, 2}, {3, 3}, {5, 5})
        }

        assert.same(expected, actual)
      end
    )
    it(
      "with only a inputs, returns as expected",
      function()
        local a = dump_params(1, 1, 2, 3, 5)
        local b = dump_params()

        local actual = dump_full_disjunction(a, b, nil, true)

        local expected = {
          a_only = dump_params(1, 1, 2, 3, 5),
          b_only = dump_params(),
          both = dump_params()
        }

        assert.same(expected, actual)
      end
    )
    it(
      "with only b inputs, returns as expected",
      function()
        local a = dump_params()
        local b = dump_params(1, 1, 2, 3, 5)

        local actual = dump_full_disjunction(a, b, nil, true)

        local expected = {
          a_only = dump_params(),
          b_only = dump_params(1, 1, 2, 3, 5),
          both = dump_params()
        }

        assert.same(expected, actual)
      end
    )
    it(
      "with partially overlapping inputs, returns as expected",
      function()
        local a = dump_params(6, 1, 0, 2, 1, 3, 5, 2, 5, 6)
        local b = dump_params(2, 9, 3, 7, 3, 3, 6, 7, 9, 5)

        local actual = dump_full_disjunction(a, b, nil, true)

        local expected = {
          a_only = dump_params(1, 0, 1, 2, 5, 6),
          b_only = dump_params(9, 7, 3, 3, 7, 9),
          both = dump_params({6, 6}, {2, 2}, {3, 3}, {5, 5})
        }

        assert.same(expected, actual)
      end
    )
  end
)

describe(
  "Test function deepish_equal()",
  function()
    it(
      "compares plainly equal values as equal",
      function()
        assert.True(deepish_equal(0, 0))
        assert.True(deepish_equal(1, 1))
        assert.True(deepish_equal("a", "a"))
        assert.True(deepish_equal(nil, nil))
      end
    )
    it(
      "compares plainly unequal values as unequal",
      function()
        assert.False(deepish_equal(0, 1))
        assert.False(deepish_equal(1, "a"))
        assert.False(deepish_equal("a", nil))
        assert.False(deepish_equal(nil, 0))
      end
    )
    it(
      "compares lists as expected",
      function()
        assert.True(deepish_equal({}, {}))
        assert.True(deepish_equal({"a", "b"}, {"a", "b"}))
        assert.True(deepish_equal({"a", nil}, {"a", nil}))
        assert.False(deepish_equal({}, {0}))
        assert.False(deepish_equal({nil, "a"}, {"a", nil}))
      end
    )
    it(
      "compares deeper lists as expected",
      function()
        assert.True(deepish_equal({{}}, {{}}))
        assert.False(deepish_equal({}, {{}}))
        assert.True(deepish_equal({1, 2, {3, 4, {5, 6}}}, {1, 2, {3, 4, {5, 6}}}))
        assert.False(deepish_equal({1, 2, {3, 4, {5, 6}}}, {1, 2, {3, 4, 5, 6}}))
      end
    )
    it(
      "compares dumps as expected",
      function()
        assert.True(deepish_equal(dump_params(), dump_params()))
        assert.True(deepish_equal(dump_array({1, 2, 3, 4}), dump_params(1, 2, 3, 4)))
        assert.True(
          deepish_equal(
            dump_params(1, dump_params(2, dump_params(3))),
            dump_array({1, dump_array({2, dump_array({3})})})
          )
        )
        assert.False(
          deepish_equal(
            dump_params(1, dump_params(2, dump_params(3))),
            dump_array({1, dump_array({2, dump_array({4})})})
          )
        )
      end
    )
  end
)

--
-- Sqib methods
--

describe(
  "Sqib:empty()",
  function()
    it(
      "returns an empty Seq",
      function()
        local seq = Sqib:empty()
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:from()",
  function()
    it(
      "with something that is_sqib_seq(), returns the value itself",
      function()
        -- Sqib:empty():is_sqib_seq() returns true; this is tried in another test
        local value = Sqib:empty()
        local seq = Sqib:from(value)
        assert.equals(value, seq)
      end
    )
    it(
      "with something where is_sqib_seq() test fails but to_sqib_seq() exists, returns its result",
      function()
        local value = {
          to_sqib_seq = function()
            return Sqib:over(1, 2, 3):map(
              function(v)
                return v * 2
              end
            )
          end
        }
        local seq = Sqib:from(value)
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "when to_sqib_seq() returns a non-sequence, raises error",
      function()
        local value = {
          to_sqib_seq = function()
            return {}
          end
        }
        assert.has_error(
          function()
            Sqib:from(value)
          end
        )
      end
    )
    it(
      "with a Seq-like table, returns the table itself",
      function()
        local value = Sqib:over(2, 4, 6)
        local seq = Sqib:from(value)
        assert.equals(value, seq)
      end
    )
    it(
      "with a packed-like table, returns a packed wrapper",
      function()
        local value = {n = 3, 2, 4, 6}
        local seq = Sqib:from(value)
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "with a table that is not Seq-like and not packed-like, returns an array wrapper",
      function()
        local value = {2, 4, 6}
        local seq = Sqib:from(value)
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "with a function, returns an iterate wrapper",
      function()
        local value = function()
          return ipairs({2, 4, 6})
        end
        local seq = Sqib:from(value)
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "with a non-sequence value, raises error",
      function()
        local value = "xyzzy"
        assert.has_error(
          function()
            Sqib:from(value)
          end
        )
      end
    )
  end
)

describe(
  "Sqib:from_all()",
  function()
    it(
      "with no parameters, returns an empty sequence",
      function()
        local seq = Sqib:from_all()
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
    it(
      "with only arrays, returns correct sequence",
      function()
        local seq = Sqib:from_all({1, 2, 3}, {4}, {5, 6}, {}, {7, 8, 9, 10})
        assert.same(dump_params(1, 2, 3, 4, 5, 6, 7, 8, 9, 10), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:from_array() (no length parameter)",
  function()
    it(
      "has the correct contents for an empty sequence",
      function()
        local seq = Sqib:from_array({})
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence of non-nils",
      function()
        local seq = Sqib:from_array({2, 4, 6})
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with a leading nil",
      function()
        local seq = Sqib:from_array({nil, 4, 6})
        assert.same(dump_params(nil, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with an inner nil",
      function()
        local seq = Sqib:from_array({2, nil, 6})
        assert.same(dump_params(2, nil, 6), dump_sqib(seq))
      end
    )
    it(
      "omits the trailing nil of a sequence with a trailing nil",
      function()
        local seq = Sqib:from_array({2, 4, nil})
        assert.same(dump_params(2, 4), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:from_array() (with length parameter)",
  function()
    it(
      "has the correct contents for an empty sequence",
      function()
        local seq = Sqib:from_array({}, 0)
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence of non-nils",
      function()
        local seq = Sqib:from_array({2, 4, 6}, 3)
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with a leading nil",
      function()
        local seq = Sqib:from_array({nil, 4, 6}, 3)
        assert.same(dump_params(nil, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with an inner nil",
      function()
        local seq = Sqib:from_array({2, nil, 6}, 3)
        assert.same(dump_params(2, nil, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with a trailing nil",
      function()
        local seq = Sqib:from_array({2, 4, nil}, 3)
        assert.same(dump_params(2, 4, nil), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:from_iterate()",
  function()
    it(
      "with builtin ipairs(), returns the expected result for an empty sequence",
      function()
        local seq =
          Sqib:from_iterate(
          function()
            return ipairs({})
          end
        )
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
    it(
      "with builtin ipairs(), returns the expected result for a sequence of non-nils",
      function()
        local seq =
          Sqib:from_iterate(
          function()
            return ipairs({2, 4, 6})
          end
        )
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for an empty sequence",
      function()
        local seq =
          Sqib:from_iterate(
          function()
            return nillable_ipairs({})
          end
        )
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for a sequence of non-nils",
      function()
        local seq =
          Sqib:from_iterate(
          function()
            return nillable_ipairs({2, 4, 6})
          end
        )
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for a sequence with a leading nil",
      function()
        local seq =
          Sqib:from_iterate(
          function()
            return nillable_ipairs({nil, 4, 6})
          end
        )
        assert.same(dump_params(nil, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "with test function nillable_ipairs(), returns the expected result for a sequence with an inner nil",
      function()
        local seq =
          Sqib:from_iterate(
          function()
            return nillable_ipairs({2, nil, 6})
          end
        )
        assert.same(dump_params(2, nil, 6), dump_sqib(seq))
      end
    )
    it(
      "with test function nillable_ipairs() (with length parameter), returns the expected result for a sequence with an trailing nil",
      function()
        local seq =
          Sqib:from_iterate(
          function()
            return nillable_ipairs({2, 4, nil}, 3)
          end
        )
        assert.same(dump_params(2, 4, nil), dump_sqib(seq))
      end
    )
    it(
      "with extra parameters, parameters are passed to the iterate function (doc example)",
      function()
        local function example_iterate(start, limit)
          local i = start - 1

          return function()
            if i < limit then
              i = i + 1
              return true, i
            end
          end
        end

        local seq = Sqib:from_iterate(example_iterate, 10, 13)

        -- first pass
        assert.same(dump_params(10, 11, 12, 13), dump_sqib(seq))
        -- second pass
        assert.same(dump_params(10, 11, 12, 13), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:from_keys()",
  function()
    it(
      "iterates the keys from a table, in any order",
      function()
        local t = {alpha = true, bravo = true, charlie = false, delta = false}
        local seq = Sqib:from_keys(t)
        local dump = dump_sqib(seq)

        local fj = dump_full_disjunction(dump_params("alpha", "bravo", "charlie", "delta"), dump)

        assert.same(
          {
            both = dump_params("alpha", "bravo", "charlie", "delta"),
            a_only = dump_params(),
            b_only = dump_params()
          },
          fj
        )
      end
    )
  end
)

describe(
  "Sqib:from_packed()",
  function()
    it(
      "has the correct contents for an empty sequence",
      function()
        local seq = Sqib:from_packed({n = 0})
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence of non-nils",
      function()
        local seq = Sqib:from_packed({n = 3, 2, 4, 6})
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with a leading nil",
      function()
        local seq = Sqib:from_packed({n = 3, nil, 4, 6})
        assert.same(dump_params(nil, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with an inner nil",
      function()
        local seq = Sqib:from_packed({n = 3, 2, nil, 6})
        assert.same(dump_params(2, nil, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with a trailing nil",
      function()
        local seq = Sqib:from_packed({n = 3, 2, 4, nil})
        assert.same(dump_params(2, 4, nil), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:from_pairs()",
  function()
    it(
      "iterates the pairs from a table, in any order",
      function()
        local t = {a = "alpha", b = "bravo", c = "charlie", d = "delta"}
        local seq = Sqib:from_pairs(t)
        local dump = dump_sqib(seq)

        local fj =
          dump_full_disjunction(dump_params({"a", "alpha"}, {"b", "bravo"}, {"c", "charlie"}, {"d", "delta"}), dump)

        assert.same(
          {
            both = dump_params({"a", "alpha"}, {"b", "bravo"}, {"c", "charlie"}, {"d", "delta"}),
            a_only = dump_params(),
            b_only = dump_params()
          },
          fj
        )
      end
    )
    it(
      "with result selector, iterates the pairs from a table, in any order",
      function()
        local t = {a = "alpha", b = "bravo", c = "charlie", d = "delta"}
        local seq =
          Sqib:from_pairs(
          t,
          function(k, v)
            return k .. "->" .. v
          end
        )
        local dump = dump_sqib(seq)

        local fj = dump_full_disjunction(dump_params("a->alpha", "b->bravo", "c->charlie", "d->delta"), dump)

        assert.same(
          {
            both = dump_params("a->alpha", "b->bravo", "c->charlie", "d->delta"),
            a_only = dump_params(),
            b_only = dump_params()
          },
          fj
        )
      end
    )
  end
)

describe(
  "Sqib:from_values()",
  function()
    it(
      "iterates the values from a table, in any order",
      function()
        local t = {a = "alpha", b = "bravo", c = "charlie", d = "delta"}
        local seq = Sqib:from_values(t)
        local dump = dump_sqib(seq)

        local fj = dump_full_disjunction(dump_params("alpha", "bravo", "charlie", "delta"), dump)

        assert.same(
          {
            both = dump_params("alpha", "bravo", "charlie", "delta"),
            a_only = dump_params(),
            b_only = dump_params()
          },
          fj
        )
      end
    )
  end
)

describe(
  "Sqib:from_yielder()",
  function()
    it(
      "runs the doc example",
      function()
        local function example_yielder(start, limit)
          for i = start, limit do
            for j = start, limit do
              coroutine.yield("(" .. i .. "," .. j .. ")")
            end
          end
        end

        local seq = Sqib:from_yielder(example_yielder, 1, 2)

        -- first pass
        assert.same(dump_params("(1,1)", "(1,2)", "(2,1)", "(2,2)"), dump_sqib(seq))
        -- second pass
        assert.same(dump_params("(1,1)", "(1,2)", "(2,1)", "(2,2)"), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:over()",
  function()
    it(
      "has the correct contents for an empty sequence",
      function()
        local seq = Sqib:over()
        assert.same(dump_params(), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence of non-nils",
      function()
        local seq = Sqib:over(2, 4, 6)
        assert.same(dump_params(2, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with a leading nil",
      function()
        local seq = Sqib:over(nil, 4, 6)
        assert.same(dump_params(nil, 4, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with an inner nil",
      function()
        local seq = Sqib:over(2, nil, 6)
        assert.same(dump_params(2, nil, 6), dump_sqib(seq))
      end
    )
    it(
      "has the correct contents for a sequence with a trailing nil",
      function()
        local seq = Sqib:over(2, 4, nil)
        assert.same(dump_params(2, 4, nil), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Sqib:range()",
  function()
    it(
      "represents the specified range",
      function()
        assert.same(dump_params(1, 2, 3, 4, 5), dump_sqib(Sqib:range(1, 5)))
        assert.same(dump_params(), dump_sqib(Sqib:range(5, 1)))
        assert.same(dump_params(), dump_sqib(Sqib:range(1, 5, -1)))
        assert.same(dump_params(5, 4, 3, 2, 1), dump_sqib(Sqib:range(5, 1, -1)))

        assert.same(dump_params(0, 3, 6, 9), dump_sqib(Sqib:range(0, 10, 3)))
        assert.same(dump_params(), dump_sqib(Sqib:range(10, 0, 3)))
        assert.same(dump_params(), dump_sqib(Sqib:range(0, 10, -3)))
        assert.same(dump_params(10, 7, 4, 1), dump_sqib(Sqib:range(10, 0, -3)))
      end
    )
  end
)

describe(
  "Sqib:times()",
  function()
    it(
      "behaves as expected for positive counts",
      function()
        assert.same(dump_params("q"), dump_sqib(Sqib:times("q", 1)))
        assert.same(dump_params("q"), dump_sqib(Sqib:times("q", 1.5)))
        assert.same(dump_params("q", "q", "q"), dump_sqib(Sqib:times("q", 3)))
        assert.same(dump_params("q", "q", "q"), dump_sqib(Sqib:times("q", 3.9)))
      end
    )
    it(
      "behaves as expected for zero count",
      function()
        assert.same(dump_params(), dump_sqib(Sqib:times("q", 0)))
        assert.same(dump_params(), dump_sqib(Sqib:times("q", 0.5)))
      end
    )
    it(
      "behaves as expected for negative count",
      function()
        assert.same(dump_params(), dump_sqib(Sqib:times("q", -1000)))
        assert.same(dump_params(), dump_sqib(Sqib:times("q", -1)))
        assert.same(dump_params(), dump_sqib(Sqib:times("q", -0.5)))
      end
    )
  end
)

--
-- Seq methods
--

describe(
  "Seq:append()",
  function()
    it(
      "appends individual elements to sequences",
      function()
        assert.same(
          dump_params("q", "w", "e", "r", "t", "y"),
          dump_sqib(Sqib:over("q", "w", "e"):append("r", "t", "y"))
        )
        assert.same(dump_params(), dump_sqib(Sqib:empty():append()))
        assert.same(dump_params("q", "w", "e"), dump_sqib(Sqib:empty():append("q", "w", "e")))
        assert.same(dump_params("q", "w", "e"), dump_sqib(Sqib:over("q", "w", "e"):append()))
      end
    )
  end
)

describe(
  "Seq:batch()",
  function()
    it(
      "trivially batches as expected",
      function()
        local source_seq = Sqib:range(1, 10)

        assert.same(dump_params({n = 10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10}), dump_sqib(source_seq:batch(11)))
        assert.same(dump_params({n = 10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10}), dump_sqib(source_seq:batch(10)))
        assert.same(dump_params({n = 9, 1, 2, 3, 4, 5, 6, 7, 8, 9}, {n = 1, 10}), dump_sqib(source_seq:batch(9)))
        assert.same(dump_params({n = 8, 1, 2, 3, 4, 5, 6, 7, 8}, {n = 2, 9, 10}), dump_sqib(source_seq:batch(8)))
        assert.same(dump_params({n = 7, 1, 2, 3, 4, 5, 6, 7}, {n = 3, 8, 9, 10}), dump_sqib(source_seq:batch(7)))
        assert.same(dump_params({n = 6, 1, 2, 3, 4, 5, 6}, {n = 4, 7, 8, 9, 10}), dump_sqib(source_seq:batch(6)))
        assert.same(dump_params({n = 5, 1, 2, 3, 4, 5}, {n = 5, 6, 7, 8, 9, 10}), dump_sqib(source_seq:batch(5)))
        assert.same(
          dump_params({n = 4, 1, 2, 3, 4}, {n = 4, 5, 6, 7, 8}, {n = 2, 9, 10}),
          dump_sqib(source_seq:batch(4))
        )
        assert.same(
          dump_params({n = 3, 1, 2, 3}, {n = 3, 4, 5, 6}, {n = 3, 7, 8, 9}, {n = 1, 10}),
          dump_sqib(source_seq:batch(3))
        )
        assert.same(
          dump_params({n = 2, 1, 2}, {n = 2, 3, 4}, {n = 2, 5, 6}, {n = 2, 7, 8}, {n = 2, 9, 10}),
          dump_sqib(source_seq:batch(2))
        )
        assert.same(
          dump_params(
            {n = 1, 1},
            {n = 1, 2},
            {n = 1, 3},
            {n = 1, 4},
            {n = 1, 5},
            {n = 1, 6},
            {n = 1, 7},
            {n = 1, 8},
            {n = 1, 9},
            {n = 1, 10}
          ),
          dump_sqib(source_seq:batch(1))
        )
      end
    )
    it(
      "batches an all-nil sequence as expected",
      function()
        local source_seq =
          Sqib:range(1, 10):map(
          function()
            return nil
          end
        )

        assert.same(
          dump_params({n = 10, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil}),
          dump_sqib(source_seq:batch(11))
        )
        assert.same(
          dump_params({n = 10, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil}),
          dump_sqib(source_seq:batch(10))
        )
        assert.same(
          dump_params({n = 9, nil, nil, nil, nil, nil, nil, nil, nil, nil}, {n = 1, nil}),
          dump_sqib(source_seq:batch(9))
        )
        assert.same(
          dump_params({n = 8, nil, nil, nil, nil, nil, nil, nil, nil}, {n = 2, nil, nil}),
          dump_sqib(source_seq:batch(8))
        )
        assert.same(
          dump_params({n = 7, nil, nil, nil, nil, nil, nil, nil}, {n = 3, nil, nil, nil}),
          dump_sqib(source_seq:batch(7))
        )
        assert.same(
          dump_params({n = 6, nil, nil, nil, nil, nil, nil}, {n = 4, nil, nil, nil, nil}),
          dump_sqib(source_seq:batch(6))
        )
        assert.same(
          dump_params({n = 5, nil, nil, nil, nil, nil}, {n = 5, nil, nil, nil, nil, nil}),
          dump_sqib(source_seq:batch(5))
        )
        assert.same(
          dump_params({n = 4, nil, nil, nil, nil}, {n = 4, nil, nil, nil, nil}, {n = 2, nil, nil}),
          dump_sqib(source_seq:batch(4))
        )
        assert.same(
          dump_params({n = 3, nil, nil, nil}, {n = 3, nil, nil, nil}, {n = 3, nil, nil, nil}, {n = 1, nil}),
          dump_sqib(source_seq:batch(3))
        )
        assert.same(
          dump_params({n = 2, nil, nil}, {n = 2, nil, nil}, {n = 2, nil, nil}, {n = 2, nil, nil}, {n = 2, nil, nil}),
          dump_sqib(source_seq:batch(2))
        )
        assert.same(
          dump_params(
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil},
            {n = 1, nil}
          ),
          dump_sqib(source_seq:batch(1))
        )
      end
    )
    it(
      "batches empty as expected",
      function()
        assert.same(dump_params(), dump_sqib(Sqib:empty():batch(1)))
      end
    )
    it(
      "uses result_selector as expected",
      function()
        local seq =
          Sqib:over(1, nil, 3, nil, 5, nil, 7, nil, 9, nil):batch(
          3,
          function(a, n)
            return {Array = a, Count = n}
          end
        )

        assert.same(
          dump_params(
            {Array = {1, nil, 3}, Count = 3},
            {Array = {nil, 5, nil}, Count = 3},
            {Array = {7, nil, 9}, Count = 3},
            {Array = {nil}, Count = 1}
          ),
          dump_sqib(seq)
        )
      end
    )
  end
)

describe(
  "Seq:call()",
  function()
    it(
      "runs the doc example correctly",
      function()
        local function my_every_n(seq, n)
          return seq:filter(
            function(_, i)
              return i % n == 0
            end
          )
        end

        local seq = Sqib:over(1, 2, 3, 4, 5, 6, 7, 8, 9, 10):call(my_every_n, 3)

        assert.same(dump_params(3, 6, 9), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Seq:concat()",
  function()
    it(
      "concatenates sequences",
      function()
        assert.same(
          dump_params("q", "w", "e", "r", "t", "y"),
          dump_sqib(Sqib:over("q", "w", "e"):concat(Sqib:over("r", "t", "y")))
        )
        assert.same(dump_params(), dump_sqib(Sqib:empty():concat(Sqib:empty())))
        assert.same(dump_params("q", "w", "e"), dump_sqib(Sqib:empty():concat(Sqib:over("q", "w", "e"))))
        assert.same(dump_params("q", "w", "e"), dump_sqib(Sqib:over("q", "w", "e"):concat()))
        assert.same(dump_params("q", "w", "e"), dump_sqib(Sqib:over("q", "w", "e"):concat(Sqib:empty())))
      end
    )
    it(
      "concatenates sequences to themselves",
      function()
        local seq = Sqib:over("q", "w", "e")
        assert.same(dump_params("q", "w", "e", "q", "w", "e", "q", "w", "e"), dump_sqib(seq:concat(seq, seq)))
      end
    )
  end
)

describe(
  "Seq:count()",
  function()
    it(
      "counts a sequence correctly",
      function()
        local t = {a = "alpha", b = "bravo", c = "charlie"}

        local seq_e = Sqib:empty()
        local seq_a3 = Sqib:from_array({2, nil, 6})
        local seq_a5 = Sqib:from_array({2, nil, 6}, 5)
        local seq_tk = Sqib:from_keys(t)
        local seq_tv = Sqib:from_values(t)
        local seq_tp = Sqib:from_pairs(t)
        local seq_p = Sqib:from_packed({n = 8, 2, 4, nil, 8, 10})
        local seq_fa = Sqib:from_all({2, nil, 6}, {n = 5, "a", nil, "c"}, seq_e, seq_a5)

        assert.equal(seq_e:count(), 0)
        assert.equal(seq_a3:count(), 3)
        assert.equal(seq_a5:count(), 5)
        assert.equal(seq_tk:count(), 3)
        assert.equal(seq_tv:count(), 3)
        assert.equal(seq_tp:count(), 3)
        assert.equal(seq_p:count(), 8)
        assert.equal(seq_fa:count(), 13)
      end
    )
    it(
      "counts elements that satisfy a predicate correctly",
      function()
        local seq = Sqib:over("alpha", "bravo", "charlie", "delta", "echo")
        assert.equal(
          3,
          seq:count(
            function(v)
              return string.len(v) == 5
            end
          )
        )
      end
    )
  end
)

describe(
  "Seq:filter()",
  function()
    it(
      "given even number predicate, filters to only even numbers",
      function()
        local seq =
          Sqib:range(1, 9):filter(
          function(v)
            return v % 2 == 0
          end
        )
        assert.same(dump_params(2, 4, 6, 8), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Seq:flat_map()",
  function()
    local seq_of_seq =
      Sqib:from_array(
      {
        Sqib:over("q", "w", "e"),
        Sqib:from_array({"r", "t", "y"}),
        Sqib:from_packed({n = 4, "u", "i", "o", "p"})
      }
    )

    local seq_of_arrays =
      Sqib:from_array(
      {
        {"q", "w", "e"},
        {"r", "t", "y"},
        {"u", "i", "o", "p"}
      }
    )

    local seq_of_strings =
      Sqib:from_array(
      {
        "qwe",
        "rty",
        "uiop"
      }
    )

    local function string_to_char_array(v)
      local len = string.len(v)
      local t = {}
      for i = 1, string.len(v) do
        t[i] = string.sub(v, i, i)
      end

      return t
    end

    local function string_to_char_seq(v)
      local t = string_to_char_array(v)
      return Sqib:from_array(t)
    end

    local expected = dump_params("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")

    it(
      "(default settings) given a Seq of Seq, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_seq:flat_map()))
      end
    )
    it(
      "(convert_result explicitly true) given a Seq of Seq, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_seq:flat_map(nil, true)))
      end
    )
    it(
      "(convert_result explicitly false) given a Seq of Seq, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_seq:flat_map(nil, false)))
      end
    )

    it(
      "(default settings) given a Seq of arrays, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_arrays:flat_map()))
      end
    )
    it(
      "(convert_result explicitly true) given a Seq of arrays, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_arrays:flat_map(nil, true)))
      end
    )
    -- Not designed to succeed if convert_result is false

    it(
      "(convert_result default) given a Seq of strings and a selector that returns a Seq, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_strings:flat_map(string_to_char_seq)))
      end
    )
    it(
      "(convert_result explicitly true) given a Seq of strings and a selector that returns a Seq, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_strings:flat_map(string_to_char_seq, true)))
      end
    )
    it(
      "(convert_result explicitly false) given a Seq of strings and a selector that returns a Seq, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_strings:flat_map(string_to_char_seq, false)))
      end
    )

    it(
      "(convert_result default) given a Seq of strings and a selector that returns an array, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_strings:flat_map(string_to_char_array)))
      end
    )
    it(
      "(convert_result explicitly true) given a Seq of strings and a selector that returns an array, produces the expected result",
      function()
        assert.same(expected, dump_sqib(seq_of_strings:flat_map(string_to_char_array, true)))
      end
    )
    -- Not designed to succeed if convert_result is false
  end
)

describe(
  "Seq:force()",
  function()
    it(
      "iterates at appropriate time",
      function()
        local map_called_count = 0

        local source_seq =
          Sqib:range(1, 10):map(
          function(v)
            map_called_count = map_called_count + 1
            return v * 2
          end
        )

        local forced_seq = source_seq:force()

        assert.equal(10, map_called_count)

        local dump_of_forced_seq = dump_sqib(forced_seq)

        assert.equal(10, map_called_count)

        local dump_of_source_seq = dump_sqib(source_seq)

        assert.equal(20, map_called_count)

        local expected = dump_params(2, 4, 6, 8, 10, 12, 14, 16, 18, 20)
        assert.same(expected, dump_of_forced_seq)
        assert.same(expected, dump_of_source_seq)
      end
    )
  end
)

describe(
  "Seq:is_sqib_seq()",
  function()
    it(
      "always returns true",
      function()
        local t = {a = "alpha", b = "bravo", c = "charlie"}

        local seq_e = Sqib:empty()
        local seq_a3 = Sqib:from_array({2, nil, 6})
        local seq_a5 = Sqib:from_array({2, nil, 6}, 5)
        local seq_tk = Sqib:from_keys(t)
        local seq_tv = Sqib:from_values(t)
        local seq_tp = Sqib:from_pairs(t)
        local seq_p = Sqib:from_packed({n = 8, 2, 4, nil, 8, 10})
        local seq_fa = Sqib:from_all({2, nil, 6}, {n = 5, "a", nil, "c"}, seq_e, seq_a5)

        assert.True(seq_e:is_sqib_seq())
        assert.True(seq_a3:is_sqib_seq())
        assert.True(seq_a5:is_sqib_seq())
        assert.True(seq_tk:is_sqib_seq())
        assert.True(seq_tv:is_sqib_seq())
        assert.True(seq_tp:is_sqib_seq())
        assert.True(seq_p:is_sqib_seq())
        assert.True(seq_fa:is_sqib_seq())
      end
    )
  end
)

-- Seq:iterate(): Called by dump_sqib(); test would be redundant

describe(
  "Seq:map()",
  function()
    it(
      "maps a sequence as expected",
      function()
        local seq =
          Sqib:over(1, 1, 2, 3, 5):map(
          function(v)
            return v * 2
          end
        )
        assert.same(dump_params(2, 2, 4, 6, 10), dump_sqib(seq))
      end
    )
  end
)

-- Seq:new(): Called through factory methods; tests for those should be sufficient

describe(
  "Seq:pack()",
  function()
    it(
      "copies sequence to a packed list",
      function()
        assert.same({n = 3, "q", "w", "e"}, Sqib:over("q", "w", "e"):pack())
        assert.same({n = 6, true, nil, false, nil, true, nil}, Sqib:over(true, nil, false, nil, true, nil):pack())
        assert.same({n = 0}, Sqib:empty():pack())
      end
    )
  end
)

describe(
  "Seq:pairs_to_hash()",
  function()
    it(
      "maps each value to itself if the selector returns v, v",
      function()
        local hash =
          Sqib:over("a", "b", "c"):pairs_to_hash(
          function(v)
            return v, v
          end
        )
        assert.same({a = "a", b = "b", c = "c"}, hash)
      end
    )
    it(
      "fails if a key appears more than once",
      function()
        assert.has_error(
          function()
            local hash =
              Sqib:over("a", "b", "c", "a"):pairs_to_hash(
              function(v)
                return v, v
              end
            )
          end
        )
      end
    )
    it(
      "maps as expected with a normal-looking selector",
      function()
        local seq = Sqib:over({"a", "alpha"}, {"b", "bravo"}, {"c", "charlie"})
        local hash =
          seq:pairs_to_hash(
          function(pair)
            return pair[1], pair[2]
          end
        )

        assert.same({a = "alpha", b = "bravo", c = "charlie"}, hash)
      end
    )
  end
)

describe(
  "Seq:reversed()",
  function()
    it(
      "reverses the sequence as given",
      function()
        assert.same(dump_params(), dump_sqib(Sqib:empty():reversed()))
        assert.same(dump_params("q"), dump_sqib(Sqib:over("q"):reversed()))
        assert.same(dump_params("e", "w", "q"), dump_sqib(Sqib:over("q", "w", "e"):reversed()))
        assert.same(dump_params("r", "e", "w", "q"), dump_sqib(Sqib:over("q", "w", "e", "r"):reversed()))
        assert.same(dump_params("t", "r", "e", "w", "q"), dump_sqib(Sqib:over("q", "w", "e", "r", "t"):reversed()))
        assert.same(
          dump_params(nil, "t", "r", "e", "w", "q"),
          dump_sqib(Sqib:over("q", "w", "e", "r", "t", nil):reversed())
        )
        assert.same(
          dump_params(nil, "t", nil, nil, nil, "q", nil),
          dump_sqib(Sqib:over(nil, "q", nil, nil, nil, "t", nil):reversed())
        )
      end
    )
    it(
      "refrains from iterating source until iteration",
      function()
        local selector_was_called = false

        local seq =
          Sqib:range(1, 5):map(
          function(v)
            selector_was_called = true
            return v
          end
        ):reversed()

        assert.False(selector_was_called)
        local iterator = seq:iterate()
        assert.True(selector_was_called)
        assert.same(
          dump_params(5, 4, 3, 2, 1),
          dump_iter(
            function()
              return iterator
            end
          )
        )
      end
    )
  end
)

describe(
  "Seq:skip()",
  function()
    local source_seq = Sqib:over("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")

    it(
      "skips exactly the specified number of elements if possible",
      function()
        assert.same(dump_params("r", "t", "y", "u", "i", "o", "p"), dump_sqib(source_seq:skip(3)))
        assert.same(dump_params(), dump_sqib(source_seq:skip(10)))
      end
    )
    it(
      "skips nothing if the specified count is <= 0",
      function()
        assert.same(dump_params("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"), dump_sqib(source_seq:skip(0)))
        assert.same(dump_params("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"), dump_sqib(source_seq:skip(-3)))
      end
    )
    it(
      "skips everything if the specified count is greater than the sequence length",
      function()
        assert.same(dump_params(), dump_sqib(source_seq:skip(15)))
      end
    )
  end
)

describe(
  "Seq:skip_while()",
  function()
    local source_seq = Sqib:over("duck", "duck", "duck", "duck", "goose", "duck", "duck")

    it(
      "skips only the part of the sequence before the predicate fails",
      function()
        assert.same(
          dump_params("goose", "duck", "duck"),
          dump_sqib(
            source_seq:skip_while(
              function(v)
                return v == "duck"
              end
            )
          )
        )
      end
    )
    it(
      "skips the whole sequence if the predicate never fails",
      function()
        assert.same(
          dump_params(),
          dump_sqib(
            source_seq:skip_while(
              function(v)
                return v ~= "bison"
              end
            )
          )
        )
      end
    )
  end
)

describe(
  "Seq:sorted()",
  function()
    it(
      "refrains from sorting until iteration",
      function()
        local comp_was_called = false

        local function comp(a, b)
          comp_was_called = true
          return a < b
        end

        local seq =
          Sqib:over(4, 5, 3, 1, 2):sorted {compare = comp}:map(
          function(v)
            return v
          end
        )

        assert.False(comp_was_called)
        assert.same(dump_params(1, 2, 3, 4, 5), dump_sqib(seq))
        assert.True(comp_was_called)
      end
    )
    it(
      "default ordering sorts numbers as expected",
      function()
        local seq = Sqib:over(4, 5, 3, 1, 2):sorted()
        assert.same(dump_params(1, 2, 3, 4, 5), dump_sqib(seq))
      end
    )
    it(
      "sorts by selection as expected",
      function()
        local seq =
          Sqib:over({s = "bravo"}, {s = "alpha"}, {s = "charlie"}, {s = "delta"}):sorted {
          by = function(v)
            return v.s
          end
        }
        assert.same(dump_params({s = "alpha"}, {s = "bravo"}, {s = "charlie"}, {s = "delta"}), dump_sqib(seq))
      end
    )
    it(
      "descending ordering sorts numbers as expected",
      function()
        local seq = Sqib:over(4, 5, 3, 1, 2):sorted {ascending = false}
        assert.same(dump_params(5, 4, 3, 2, 1), dump_sqib(seq))
      end
    )
    it(
      "combines multiple orderings as expected",
      function()
        local seq =
          Sqib:over(
          {n = 2, a = "b", w = "*"},
          {n = 1, a = "a", w = "*"},
          {n = 1, a = "a", w = "***"},
          {n = 2, a = "c", w = "***"},
          {n = 2, a = "c", w = "**"},
          {n = 3, a = "a", w = "*"},
          {n = 2, a = "a", w = "***"},
          {n = 1, a = "b", w = "*"},
          {n = 3, a = "c", w = "*"},
          {n = 2, a = "b", w = "**"},
          {n = 1, a = "c", w = "**"},
          {n = 1, a = "b", w = "***"},
          {n = 3, a = "c", w = "**"},
          {n = 2, a = "a", w = "**"},
          {n = 2, a = "a", w = "*"},
          {n = 2, a = "b", w = "***"},
          {n = 3, a = "a", w = "**"},
          {n = 2, a = "c", w = "*"},
          {n = 3, a = "a", w = "***"},
          {n = 1, a = "a", w = "**"},
          {n = 3, a = "b", w = "**"},
          {n = 1, a = "b", w = "**"},
          {n = 3, a = "b", w = "***"},
          {n = 1, a = "c", w = "*"},
          {n = 1, a = "c", w = "***"},
          {n = 3, a = "b", w = "*"},
          {n = 3, a = "c", w = "***"}
        ):sorted(
          {
            by = function(v)
              return v.n
            end
          },
          {
            by = function(v)
              return v.a
            end,
            ascending = false
          },
          {
            by = function(v)
              return string.len(v.w)
            end
          }
        )

        local expected =
          dump_params(
          {n = 1, a = "c", w = "*"},
          {n = 1, a = "c", w = "**"},
          {n = 1, a = "c", w = "***"},
          {n = 1, a = "b", w = "*"},
          {n = 1, a = "b", w = "**"},
          {n = 1, a = "b", w = "***"},
          {n = 1, a = "a", w = "*"},
          {n = 1, a = "a", w = "**"},
          {n = 1, a = "a", w = "***"},
          {n = 2, a = "c", w = "*"},
          {n = 2, a = "c", w = "**"},
          {n = 2, a = "c", w = "***"},
          {n = 2, a = "b", w = "*"},
          {n = 2, a = "b", w = "**"},
          {n = 2, a = "b", w = "***"},
          {n = 2, a = "a", w = "*"},
          {n = 2, a = "a", w = "**"},
          {n = 2, a = "a", w = "***"},
          {n = 3, a = "c", w = "*"},
          {n = 3, a = "c", w = "**"},
          {n = 3, a = "c", w = "***"},
          {n = 3, a = "b", w = "*"},
          {n = 3, a = "b", w = "**"},
          {n = 3, a = "b", w = "***"},
          {n = 3, a = "a", w = "*"},
          {n = 3, a = "a", w = "**"},
          {n = 3, a = "a", w = "***"}
        )

        assert.same(expected, dump_sqib(seq))
      end
    )
    it(
      "sorts stably when stable is set",
      function()
        -- A sequence that matches its natural ordering.
        local natural_sequence = {
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
          17,
          18,
          19
        }

        -- A sequence that meaningfully doesn't match its natural ordering.
        -- A sort on some other field should produce a result that matches
        -- this if the sort is stable.
        local contrived_sequence = {
          "Q",
          "W",
          "E",
          "R",
          "T",
          "Y",
          "U",
          "I",
          "O",
          "P",
          "A",
          "S",
          "D",
          "F",
          "G",
          "H",
          "J",
          "K",
          "L",
          "M"
        }

        local out_index

        out_index = 0
        local by_contrived = {}
        for _, c in ipairs(contrived_sequence) do
          for _, n in ipairs(natural_sequence) do
            out_index = out_index + 1
            by_contrived[out_index] = {c = c, n = n}
          end
        end

        out_index = 0
        local by_natural = {}
        for _, n in ipairs(natural_sequence) do
          for _, c in ipairs(contrived_sequence) do
            out_index = out_index + 1
            by_natural[out_index] = {c = c, n = n}
          end
        end

        local seq =
          Sqib:from_array(by_contrived):sorted {
          by = function(v)
            return v.n
          end,
          stable = true
        }

        assert.same(dump_array(by_natural), dump_sqib(seq))
      end
    )
    it(
      "handles compare correctly if some compare results are nil and others aren't (bugfix)",
      function()
        local seq =
          Sqib:over(
          {x = "q", z = 10},
          {x = "w", z = 10},
          {x = "e"},
          {x = "r", z = 20},
          {x = "t", z = 5},
          {x = "y"},
          {x = "u", z = 5}
        ):sorted {
          by = function(v)
            return v.z
          end,
          compare = function(a, b)
            if a == nil then
              return b == nil and 0 or -1
            elseif b == nil then
              return 1
            else
              return (a < b) and -1 or (a > b) and 1 or 0
            end
          end,
          stable = true
        }:map(
          function(v)
            return v.x
          end
        )

        assert.same(dump_params("e", "y", "t", "u", "q", "w", "r"), dump_sqib(seq))
      end
    )
  end
)

describe(
  "Seq:take()",
  function()
    local source_seq = Sqib:over("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")

    it(
      "takes exactly the specified number of elements if possible",
      function()
        assert.same(dump_params("q", "w", "e"), dump_sqib(source_seq:take(3)))
        assert.same(dump_params("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"), dump_sqib(source_seq:take(10)))
      end
    )
    it(
      "takes nothing if the specified count is <= 0",
      function()
        assert.same(dump_params(), dump_sqib(source_seq:take(0)))
        assert.same(dump_params(), dump_sqib(source_seq:take(-3)))
      end
    )
    it(
      "takes everything if the specified count is greater than the sequence length",
      function()
        assert.same(dump_params("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"), dump_sqib(source_seq:take(15)))
      end
    )
  end
)

describe(
  "Seq:take_while()",
  function()
    local source_seq = Sqib:over("duck", "duck", "duck", "duck", "goose", "duck", "duck")

    it(
      "takes only the part of the sequence before the predicate fails",
      function()
        assert.same(
          dump_params("duck", "duck", "duck", "duck"),
          dump_sqib(
            source_seq:take_while(
              function(v)
                return v == "duck"
              end
            )
          )
        )
      end
    )
    it(
      "takes the whole sequence if the predicate never fails",
      function()
        assert.same(
          dump_params("duck", "duck", "duck", "duck", "goose", "duck", "duck"),
          dump_sqib(
            source_seq:take_while(
              function(v)
                return v ~= "bison"
              end
            )
          )
        )
      end
    )
  end
)

describe(
  "Seq:times()",
  function()
    local source_seq = Sqib:over("q", "w", "e")

    it(
      "produces no elements if count <= 0",
      function()
        assert.same(dump_params(), dump_sqib(source_seq:times(0)))
        assert.same(dump_params(), dump_sqib(source_seq:times(0.5)))
        assert.same(dump_params(), dump_sqib(source_seq:times(-10)))
      end
    )
    it(
      "produces as specified if count > 0",
      function()
        assert.same(dump_params("q", "w", "e"), dump_sqib(source_seq:times(1)))
        assert.same(dump_params("q", "w", "e"), dump_sqib(source_seq:times(1.9)))
        assert.same(dump_params("q", "w", "e", "q", "w", "e", "q", "w", "e"), dump_sqib(source_seq:times(3)))
        assert.same(dump_params("q", "w", "e", "q", "w", "e", "q", "w", "e"), dump_sqib(source_seq:times(3.9)))
      end
    )
    it(
      "doesn't cache by itself",
      function()
        local list = {"q", "w"}
        local function iterate()
          local i = 0
          return function()
            if i < #list then
              i = i + 1
              return i, list[i]
            end
          end
        end

        local mutable_seq = Sqib:from_iterate(iterate)
        local seq = mutable_seq:times(3)

        -- We're making `mutable_seq` a moving target to demonstrate that no caching is taking place.
        local iter = seq:iterate()
        assert.same({1, "q"}, {iter()})
        assert.same({2, "w"}, {iter()})
        list[3] = "e"
        assert.same({3, "e"}, {iter()})
        assert.same({4, "q"}, {iter()})
        assert.same({5, "w"}, {iter()})
        assert.same({6, "e"}, {iter()})
        list[4] = "r"
        assert.same({7, "r"}, {iter()})
        assert.same({8, "q"}, {iter()})
        assert.same({9, "w"}, {iter()})
        assert.same({10, "e"}, {iter()})
        assert.same({11, "r"}, {iter()})
        list[5] = "t"
        assert.same({12, "t"}, {iter()})
        assert.same({}, {iter()})
      end
    )
  end
)

describe(
  "Seq:to_array() (no include_length param)",
  function()
    it(
      "copies sequence to an array",
      function()
        assert.same({"q", "w", "e"}, Sqib:over("q", "w", "e"):to_array())
        assert.same({true, nil, false, nil, true, nil}, Sqib:over(true, nil, false, nil, true, nil):to_array())
        assert.same({}, Sqib:empty():to_array())
      end
    )
  end
)

describe(
  "Seq:to_array() (include_length param set true)",
  function()
    it(
      "copies sequence to an array and includes length",
      function()
        assert.same({{"q", "w", "e"}, 3}, {Sqib:over("q", "w", "e"):to_array(true)})
        assert.same(
          {{true, nil, false, nil, true, nil}, 6},
          {Sqib:over(true, nil, false, nil, true, nil):to_array(true)}
        )
        assert.same({{}, 0}, {Sqib:empty():to_array(true)})
      end
    )
  end
)

describe(
  "Seq:to_hash()",
  function()
    it(
      "maps each value to itself if no selectors are provided",
      function()
        local hash = Sqib:over("a", "b", "c"):to_hash()
        assert.same({a = "a", b = "b", c = "c"}, hash)
      end
    )
    it(
      "fails if a key appears more than once",
      function()
        assert.has_error(
          function()
            local hash = Sqib:over("a", "b", "c", "a"):to_hash()
          end
        )
      end
    )
    it(
      "uses selectors if they are provided",
      function()
        local seq = Sqib:over({"a", "alpha"}, {"b", "bravo"}, {"c", "charlie"})
        local hash =
          seq:to_hash(
          function(pair)
            return pair[1]
          end,
          function(pair)
            return pair[2]
          end
        )
        assert.same({a = "alpha", b = "bravo", c = "charlie"}, hash)
      end
    )
  end
)

describe(
  "Seq:to_sqib_seq()",
  function()
    it(
      "returns the exact Seq it was called on",
      function()
        local t = {a = "alpha", b = "bravo", c = "charlie"}

        local seq_e = Sqib:empty()
        local seq_a3 = Sqib:from_array({2, nil, 6})
        local seq_a5 = Sqib:from_array({2, nil, 6}, 5)
        local seq_tk = Sqib:from_keys(t)
        local seq_tv = Sqib:from_values(t)
        local seq_tp = Sqib:from_pairs(t)
        local seq_p = Sqib:from_packed({n = 8, 2, 4, nil, 8, 10})
        local seq_fa = Sqib:from_all({2, nil, 6}, {n = 5, "a", nil, "c"}, seq_e, seq_a5)

        assert.equal(seq_e, seq_e:to_sqib_seq())
        assert.equal(seq_a3, seq_a3:to_sqib_seq())
        assert.equal(seq_a5, seq_a5:to_sqib_seq())
        assert.equal(seq_tk, seq_tk:to_sqib_seq())
        assert.equal(seq_tv, seq_tv:to_sqib_seq())
        assert.equal(seq_tp, seq_tp:to_sqib_seq())
        assert.equal(seq_p, seq_p:to_sqib_seq())
        assert.equal(seq_fa, seq_fa:to_sqib_seq())
      end
    )
  end
)

describe(
  "Seq:unique()",
  function()
    local source_seq = Sqib:over("The", "first", "to", "the", "second", "to", "the", "third")
    it(
      "given a sequence of natural values, removes duplicates",
      function()
        assert.same(dump_params("The", "first", "to", "the", "second", "third"), dump_sqib(source_seq:unique()))
      end
    )
    it(
      "given a sequence of natural values and a normalizing selector, removes duplicates",
      function()
        assert.same(
          dump_params("The", "first", "to", "second", "third"),
          dump_sqib(
            source_seq:unique(
              function(v)
                return string.lower(v)
              end
            )
          )
        )
      end
    )
    it(
      "given a sequence that contains natural values and nils, removes duplicates",
      function()
        local seq = Sqib:over("The", nil, "to", "the", nil, "to", "the", nil)
        assert.same(dump_params("The", nil, "to", "the"), dump_sqib(seq:unique()))
      end
    )
  end
)

describe(
  "Seq:unpack()",
  function()
    it(
      "inlines as parameters identically to the input",
      function()
        assert.same(dump_params(), dump_params(Sqib:over():unpack()))
        assert.same(dump_params(1, 2, 3), dump_params(Sqib:over(1, 2, 3):unpack()))
        assert.same(dump_params(1, 2, 3, 4), dump_params(Sqib:over(1, 2, 3, 4):unpack()))
        assert.same(dump_params(1, 2, 3, 4, 5, 6), dump_params(Sqib:over(1, 2, 3, 4, 5, 6):unpack()))
        assert.same(dump_params(1, 2, 3, 4, 5, 6, 7, 8), dump_params(Sqib:over(1, 2, 3, 4, 5, 6, 7, 8):unpack()))
        assert.same(dump_params(nil, nil, nil), dump_params(Sqib:over(nil, nil, nil):unpack()))
      end
    )
    it(
      "handles a pretty substantially long sequence with embedded and trailing nils without trouble",
      function()
        local function make_big_example_array()
          local a = {}
          local n = 0

          for i = 1, 300 do
            n = n + 1
            a[n] = i
            n = n + 1
            a[i] = nil
          end

          return a, n
        end

        -- A copy for expected
        local ea, en = make_big_example_array()

        -- Another copy for the sequence
        local sa, sn = make_big_example_array()

        local seq = Sqib:from_array(sa, sn)

        assert.same(dump_array(ea, en), dump_params(seq:unpack()))
      end
    )
  end
)
