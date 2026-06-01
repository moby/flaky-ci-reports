-- docker-py-test-fail: pytest in moby's docker-py integration suite
-- emits a FAILURES section after the test run:
--   =================================== FAILURES ===================================
--   ___________________ <TestClass.test_method> ___________________
--   <traceback>
--   ___________________ <TestClass.test_method2> ___________________
--   ...
--   =========================== short test summary info ============================
--
-- The underscore-banner names each failed test. Distinct from
-- go-test-failure (different test framework, different surface). Each
-- failed test becomes its own `docker-py-test:<TestClass.test_method>`
-- observation so flaky pytest tests are tracked per-test.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  local in_failures = false
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    if line:match("=+ FAILURES =+") then
      in_failures = true
    elseif in_failures and line:match("=+ short test summary info =+") then
      break
    elseif in_failures then
      -- Underscore banner: `___+ <TestClass.test_method> ___+`
      local name = line:match("^[^Z]*Z _+%s+(%S+)%s+_+%s*$")
      if name and not seen[name] then
        seen[name] = true
        table.insert(out, {
          unique_key = "docker-py-test:" .. name,
          name       = "docker-py test failed: " .. name,
          category   = "test",
          fields     = { test_name = name },
          evidence   = { { start_line = i, end_line = i } },
        })
      end
    end
  end
  return out
end
