package.path = "tests/?.lua;" .. package.path
local T = require("harness")

-- The game runs Lua 5.1. LuaJIT, which these tests run on, accepts a handful of 5.2 things
-- that the client will not even load, so nothing shipped may use them.
local BANNED = {
  { "%f[%w]goto%f[%W]", "goto, which Lua 5.1 has no idea about" },
  { "::%a[%w_]*::", "a goto label" },
  { "%d%s*//%s*%d", "the 5.3 integer division operator" },
  -- "cond and unpack(a) or unpack(b)" hands the caller one value instead of three, so
  -- SetTextColor gets a red and no green or blue and throws. The fake client shrugs at it and
  -- the game does not, which is exactly the kind of thing a lint is for.
  { "[%s(]and%s+unpack%(", "unpack inside a conditional, which keeps only its first value" },
  { "[%s(]or%s+unpack%(", "unpack inside a conditional, which keeps only its first value" },
}

local function files()
  local out = {}
  local pipe = io.popen("ls *.lua */*.lua 2>/dev/null")
  for line in pipe:lines() do
    if not line:match("^tests/") then table.insert(out, line) end
  end
  pipe:close()
  return out
end

T.run("nothing shipped uses syntax the game cannot load", function()
  local checked, complaints = 0, {}
  for _, path in ipairs(files()) do
    local handle = io.open(path, "r")
    if handle then
      local text = handle:read("*a")
      handle:close()
      checked = checked + 1
      for _, rule in ipairs(BANNED) do
        local found = text:match(rule[1])
        if found then
          table.insert(complaints, ("%s uses %s (%s)"):format(path, found, rule[2]))
        end
      end
    end
  end
  T.truthy(checked > 20, "only checked " .. checked .. " files")
  T.eq(#complaints, 0, table.concat(complaints, "; "))
end)

T.finish()
