-- go-test-failure: catches per-test failures in Go test output via three
-- complementary signals:
--   1. GitHub annotation : "##[error]=== RUN   TestX/SubY/worker=W"
--   2. Standard Go test  : "--- FAIL: TestX/SubY/worker=W (1.23s)"
--   3. Summary block     : "=== FAIL: <pkg> TestX/SubY/worker=W (1.23s)"
-- The third form is the only signal when a test *panics* before reaching
-- the standard "--- FAIL:" output (e.g. dap TestLaunch panic in test-unit
-- jobs). All three signals produce the same unique_key shape so
-- per-attempt dedup collapses duplicates.
--
-- worker= matrix dimension becomes a tag so all failures of the same
-- test across the matrix collapse into one group. buildx tests use
-- only worker= (no frontend= / slice= like buildkit).

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    -- Strip ANSI colour codes (summary-block form uses them).
    local clean = line:gsub("\27%[[0-9;]*m", "")

    local path = clean:match("^[^Z]*Z ##%[error%]=== RUN%s+(.+)$")
    if not path then
      -- Trim the "(1.23s)" duration suffix; ignore the indent prefix.
      path = clean:match("^[^Z]*Z%s*%-%-%- FAIL:%s+(%S+)")
    end
    if not path then
      -- `=== FAIL: <pkg> <test> (1.23s)` — pkg precedes test, drop it.
      local _, t = clean:match("^[^Z]*Z%s*=== FAIL:%s+(%S+)%s+(%S+)")
      path = t
    end

    if path then
      local bare, tags = extract_tags(path, {"worker"})
      -- Drop the bare framework wrapper — the inner subtests are the cause.
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
  return out
end
