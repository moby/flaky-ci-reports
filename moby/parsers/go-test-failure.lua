-- go-test-failure: catches Go test failures via four complementary signals:
--
--   1. GitHub annotation : `##[error]=== RUN   TestX/SubY/worker=W/slice=N-M`
--   2. Standard Go test  : `--- FAIL: TestX/SubY/worker=W/slice=N-M (1.23s)`
--   3. Summary block     : `=== FAIL: <pkg> TestX/SubY/worker=W (1.23s)`
--   4. Bare package FAIL : `FAIL\tgithub.com/moby/moby/v2/<pkg>\t<duration>` —
--      gotestsum / `go test` prints this summary line when a test panicked
--      or hit `t.Fatal()` without ever reaching the `--- FAIL:` output.
--      Common in moby for networkdb deadlock & fluentd transport tests.
--      Emitted only when signals 1-3 produce *nothing* in the log;
--      otherwise we'd double-count the same failure as both a per-test
--      and a per-pkg observation.
--
-- Worker / frontend / slice matrix dimensions become tags so all
-- failures of the same test across the matrix collapse into one group.
-- buildkit-style matrix axes carry over to moby integration tests.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    -- Strip ANSI colour codes (summary form sometimes uses them).
    local clean = line:gsub("\27%[[0-9;]*m", "")

    local path = clean:match("^[^Z]*Z ##%[error%]=== RUN%s+(.+)$")
    if not path then
      path = clean:match("^[^Z]*Z%s*%-%-%- FAIL:%s+(%S+)")
    end
    if not path then
      local _, t = clean:match("^[^Z]*Z%s*=== FAIL:%s+(%S+)%s+(%S+)")
      path = t
    end

    if path then
      local bare, tags = extract_tags(path, {"worker", "frontend", "slice"})
      if bare ~= "TestIntegration" and bare ~= "" then
        local key = "go-test:" .. bare
        if not seen[key] then
          seen[key] = true
          table.insert(out, {
            unique_key = key,
            name       = bare .. " failed",
            category   = "test",
            fields     = { test_path = path },
            tags       = tags,
            evidence   = { { start_line = i, end_line = i } },
          })
        end
      end
    end
  end

  -- Fallback: per-test FAIL not found anywhere — surface pkg-level FAIL.
  if #out == 0 then
    for i, line in ipairs(log.lines) do
      local pkg = line:match("^[^Z]*Z FAIL%s+(github%.com/%S+)%s+%S+s%s*$")
      if pkg then
        local key = "go-test-pkg-fail:" .. pkg
        if not seen[key] then
          seen[key] = true
          table.insert(out, {
            unique_key = key,
            name       = pkg .. " package FAIL (no per-test FAIL line)",
            category   = "test",
            fields     = { package = pkg },
            evidence   = { { start_line = i, end_line = i } },
          })
        end
      end
    end
  end

  return out
end
