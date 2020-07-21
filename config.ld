
-- Use `ldoc .` to build docs.
-- Install `lua-discount` if necessary.

-- Note: Rendering of nested lists is subject to the issue at <https://github.com/stevedonovan/LDoc/issues/162>. Other
-- Markdown viewers don't seem to have a problem with it.

title = "Sqib documentation"
project = "Sqib"

format = 'discount'
sort = true
readme = 'README.md'

description = [[
Sqib is a fluent sequence processor for Lua.
]]

alias("p", "param")
file = {'src/Sqib.lua'}
new_type("macro","Macros")

