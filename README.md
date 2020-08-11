Sqib
====

Synopsis
--------

```lua
    -- Get a Sqib sequence

    -- From parameters (preserves trailing nils)
    local seq = Sqib.over(2, 4, 6, 8, 10, 12)

    -- From a packed list (preserves trailing nils)
    local seq = Sqib.from_packed({ n=6, 2, 4, 6, 8, 10, 12 })
    -- From array (discards trailing nils)
    local seq = Sqib.from_array({ 2, 4, 6, 8, 10, 12 })
    -- From array with explicit length (preserves trailing nils)
    local seq = Sqib.from_array({ 2, 4, 6, 8, 10, 12 }, 6)
    -- From a yielding function (a simple way to get from a for loop to a sequence)
    local seq = Sqib.from_yielder(function()
      for i=2,12,2 do
        -- Produce one element at a time using coroutine.yield(i)
        coroutine.yield(i)
      end
    end)

    -- If it's an object that `Sqib.from()` knows how to detect, you can use it instead

    -- From a packed list (preserves trailing nils)
    local seq = Sqib.from({ n=6, 2, 4, 6, 8, 10, 12 })
    -- From array (discards trailing nils)
    local seq = Sqib.from({ 2, 4, 6, 8, 10, 12 })
    -- From a yielding function
    local seq = Sqib.from(function()
      for i=2,12,2 do
        coroutine.yield(i)
      end
    end)

    -- Apply operations fluently
    local result_seq = seq
      :map(function(n) return n / 2 end)
      :filter(function(n) return n % 2 ~= 0 end)

    -- Get the result as an array
    local result_array = result_seq:to_array()

    -- Or as a packed list
    local result_packed = result_seq:pack()

    -- Or iterate over the result directly
    for i, v in result_seq:iterate() do
      do_something(i, v)
    end

    -- Do a bunch of the above without intermediate variables
    local result_packed = Sqib.over(2, 4, 6, 8, 10, 12)
      :map(function(n) return n / 2 end)
      :filter(function(n) return n % 2 end)
      :pack()
```

Features
--------

This library is for doing fluent things with sequences (in a similar fashion to Scala's `scala.collection.Seq`, .NET's `IEnumerable`, and so forth).

Where, for instance, [one functional library](http://lua-users.org/wiki/FunctionalLibrary) might operate on a sequence using awkwardly nested calls, Sqib wraps the sequence in an object and allows operations to be defined fluently, in the intuitive order. Then, a final operation is used to convert the sequence into something useful (an array, a `for` loop, etc.).

Most operations are deferred, meaning that they are not applied until the sequence is actually iterated. This means deeper call stacks but fewer intermediate arrays.

You might use this library if you want to do functional things with sequences and:

*   Functional considerations
    *   **You believe nil is a real value.** Iteration over a sequence won't accidentally stop if it hits a `nil` element.
        *   (Due the implementation of the Lua's unary `#` operator, trailing `nil`s from an array are dropped if no explicit length is specified. To work around this, specify a length parameter on `from_array()` or set the `n` field to the length to make the array a packed list.)
    *   **You want to do things with sequences declaratively, without worrying about the details.** In many cases, activities such as mapping, filtering, and sorting are easier to understand, less verbose, and just less hairy with this module than the equivalent `for` loop.
    *   **You don't want to modify the original.** As a rule, operations on sequences don't mutate their source.
    *   **You value deferred rather than instant execution.** In general, a sequence object returned by a method on another sequence object generally won't iterate over and process its source until it is iterated itself. (`force()` is an intentional exception.) Even operations that require a copy of the entire sequence (such as `sorted()` and `reversed()`) aren't actually copied until requested for iteration.
    *   **You want to apply extremely flexible sorting.** The `sorted()` method directly supports selector functions (i.e. "sort by" behavior), compare functions, optional descending order, and optional stable sorting. Additional orderings can be specified (i.e. "then by" behavior) to break ties, each with their own parameters. And the original sequence is not modified in place.
    *   **You want sequences to do new tricks.** New methods can be patched onto the `Sqib.Seq` type if you need something specific not already covered, or the `call()` method can be used to apply a function fluently without modifying the table.
*   Installation considerations
    *   **You don't want to install anything else.** This module has no external dependencies.
    *   **You want to be able to drop a file in instead of dealing with a proper package manager.** This module is designed for an environment where using LuaRocks isn't practical.

Caveats
-------

If you're operating in a more serious or complete Lua environment, there are no doubt other libraries you should be using instead of this one.

Users are warned that:

*   I'm a developer (and a big fan of LINQ, if it wasn't obvious) but I'm not a Lua expert, so I'm learning as I go and some of this code won't be as idiomatic as it should.
*   Some parts are implemented with efficiency in mind, other parts less so.
*   The code in its current state scratches the proverbial itch it was intended to address, so maintenance or improvements by me are likely to be sporadic at best. Likewise, I don't have much reason to try to package and submit this module to e.g. LuaRocks.
    *   If you like this lib enough that you are willing to improve it, package it, and/or maintain it, you absolutely have my blessing to fork the repo. Drop me a line or a pull request if you do; I'd be curious to see it.
*   I've run all the code through the `vscode-lua` formatter. I acknowledge that some of its ideas are baffling and probably un-idiomatic, but at least they're consistent, and I don't have to worry about whether some commas have spaces after them while others don't.
    *   If you know a better-looking alternative, please suggest it.
*   (My version of) this module targets Lua 5.1 and nothing older or newer.
    *   My present Lua coding efforts are in the service of developing a theme for StepMania, which is currently still based on Lua 5.1.

Name
----

Sqib unofficially stands for "**S**equence **q**uery l**ib**rary".

Sqib also unofficially stands for "**S**equence **q**uery for **i**mpatient <s>**b**as</s><ins>fools</ins>".

Project
-------

[This project is available on Github.](https://github.com/psmay/sqib)

Copyright/License
-----------------

Sqib, a sequence query facility for Lua

Copyright © 2020 psmay

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
