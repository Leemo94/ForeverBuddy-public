-- Minimal test runner for luajit. Usage: local T = require("harness")
local T = { passed = 0, failed = 0 }

local function fmt(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(msg or "eq", fmt(expected), fmt(actual)), 2)
  end
end

function T.near(actual, expected, msg, eps)
  eps = eps or 1e-6
  if type(actual) ~= "number" or math.abs(actual - expected) > eps then
    error(("%s: expected %s, got %s"):format(msg or "near", tostring(expected), tostring(actual)), 2)
  end
end

function T.truthy(v, msg)
  if not v then error((msg or "truthy") .. ": got " .. tostring(v), 2) end
end

function T.skip(name, reason)
  print("skip " .. name .. " (" .. reason .. ")")
end

function T.run(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    T.passed = T.passed + 1
    print("ok   " .. name)
  else
    T.failed = T.failed + 1
    print("FAIL " .. name .. "\n     " .. tostring(err))
  end
end

function T.finish()
  print(("%d passed, %d failed"):format(T.passed, T.failed))
  os.exit(T.failed == 0 and 0 or 1)
end

return T
