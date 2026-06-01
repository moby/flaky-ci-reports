-- panic-test-timed-out: the Go testing framework prints
--   panic: test timed out after <duration>
--   running tests:
--           TestX (<dur>)
--           ...
-- when the per-test or whole-binary timeout fires. The duration is
-- dropped from the key (40m0s today, could change). The "running tests"
-- block usually lists one test; use it as the test tag. If the block is
-- empty or absent, fall back to a key without a test.
--
-- Overrides go-test-failure: when the binary times out, all per-test
-- FAIL annotations after the panic are downstream noise (every test
-- in flight gets aborted). Tag the test that triggered it.

overrides = { "go-test-failure" }

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("^[^Z]*Z panic: test timed out after ") then
      -- Walk forward for the "running tests:" marker. The block lists one
      -- or more in-flight tests; the wrapper (e.g. bare `TestIntegration`)
      -- often appears first and the actual subtest second. Prefer a
      -- subtest path (contains `/`) over the wrapper.
      local test_path = nil
      for j = i + 1, math.min(i + 30, #log.lines) do
        if log.lines[j]:match("running tests:") then
          for k = j + 1, math.min(j + 10, #log.lines) do
            local t = log.lines[k]:match("^[^Z]*Z%s+(%S+) %(")
            if not t then
              -- blank or end-of-block — stop scanning.
              if log.lines[k]:match("^[^Z]*Z%s*$") then break end
            else
              if t:find("/") then
                test_path = t
                break
              elseif not test_path then
                test_path = t
              end
            end
          end
          break
        end
      end

      local bare, tags = nil, {}
      if test_path then
        bare, tags = extract_tags(test_path, {"worker", "frontend", "slice"})
        if bare == "TestIntegration" or bare == "" then bare = nil end
      end
      local key = bare and ("panic-test-timed-out:" .. bare) or "panic-test-timed-out"
      if bare then tags.test = bare end
      return {
        unique_key = key,
        name       = bare and ("Test timed out: " .. bare) or "Test binary timed out",
        category   = "test",
        fields     = { test_path = test_path },
        tags       = tags,
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
