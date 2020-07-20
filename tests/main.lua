
-- busted --lua=lua5.1 tests/main.lua

local Sqib = require 'Sqib'

describe("Sqib:from() and s:to_list()", function()
  it("have the same contents if none are nil", function()
    local s = Sqib:from(1, 1, 2, 3, 5)

  end)
end)

describe("Sqib:from_list() and s:to_list()", function()
  it("are the same contents but not the same object", function()
    local source_list = { 1, 1, nil, 3, 5 }
    local s = Sqib:from_list(source_list)
    local result_list = s:to_list()
    assert.are.same(source_list, result_list)
    assert.are.not_equal(source_list, result_list)
  end)
end)

describe("Sqib:from_list", function()
  it("iterates a normal list as expected", function()
    local actual = Sqib:from_list({ 1, 1, 2, 3, 5 })

    local actual_copied = {}

    for i, v in actual:ipairs() do
      actual_copied[i] = v
    end

    local expected = { 1, 1, 2, 3, 5 }

    assert.are.same(expected, actual_copied)
  end)

  it("includes nil as expected", function()
    local actual = Sqib:from_list({ 1, 2, nil, 4, 5 })

    local actual_copied = {}

    for i, v in actual:ipairs() do
      actual_copied[i] = v
    end

    local expected = { 1, 2, nil, 4, 5 }

    assert.are.same(expected, actual_copied)
  end)

end)

describe("some assertions", function()

  it("tests positive assertions", function()
    assert.is_true(true)  -- Lua keyword chained with _
    assert.True(true)     -- Lua keyword using a capital
    assert.are.equal(1, 1)
    assert.has.errors(function() error("this should fail") end)
  end)

  it("tests negative assertions", function()
    assert.is_not_true(false)
    assert.are_not.equals(1, "1")
    assert.has_no.errors(function() end)
  end)
end)
