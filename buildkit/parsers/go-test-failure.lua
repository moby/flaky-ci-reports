-- go-test-failure: catches per-test failures in Go test output via two
-- complementary signals:
--   1. GitHub annotation: "##[error]=== RUN   TestX/SubY/worker=W/frontend=F"
--   2. Standard Go test:  "--- FAIL: TestX/SubY/worker=W/frontend=F (1.23s)"
-- Both produce the same unique_key shape so per-attempt dedup collapses
-- duplicates if the same test appears via both signals.
--
-- worker= and frontend= matrix dimensions become tags so all failures of
-- the same test across the matrix collapse into one group.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  -- Pass 1: collect every failing test, collapsed to <Suite>/<TestName> (the
  -- first two path segments — t.Run sub-scenarios below that are the same
  -- failure), with its matrix tags.
  local cands = {}      -- ordered list of { bare, tags, line, path }
  local present = {}    -- set of collapsed bares, for parent-prefix dropping
  for i, line in ipairs(log.lines) do
    local path = line:match("^[^Z]*Z ##%[error%]=== RUN%s+(.+)$")
    if not path then
      -- Trim the "(1.23s)" duration suffix; ignore the indent prefix.
      path = line:match("^[^Z]*Z%s*%-%-%- FAIL:%s+(%S+)")
    end
    if path then
      local bare, tags = extract_tags(path, {"worker", "frontend", "slice"})
      if bare ~= "TestIntegration" and bare ~= "" then
        local a, b = bare:match("^([^/]+)/([^/]+)")
        if a and b then bare = a .. "/" .. b end
        table.insert(cands, { bare = bare, tags = tags, line = i, path = path })
        present[bare] = true
      end
    end
  end

  -- Pass 2: drop any candidate that is a strict path-prefix of another failing
  -- test (Go FAILs the parent only because a child did — e.g. the bare suite
  -- wrapper "TestClientGatewayIntegration" when "…/TestFoo" also failed). Emit
  -- the survivors deduped by test + matrix variant, so the same test failing
  -- across workers stays separate (real per-worker breakdown) while nested
  -- subtests of one variant collapse to one.
  local out = {}
  local seen = {}
  for _, c in ipairs(cands) do
    local is_parent = false
    for other in pairs(present) do
      if other ~= c.bare and other:sub(1, #c.bare + 1) == c.bare .. "/" then
        is_parent = true
        break
      end
    end
    if not is_parent then
      local key = "go-test:" .. c.bare
      local dkey = key .. "|" .. (c.tags.worker or "") .. "|" ..
                   (c.tags.frontend or "") .. "|" .. (c.tags.slice or "")
      if not seen[dkey] then
        seen[dkey] = true
        table.insert(out, {
          unique_key = key,
          name       = c.bare .. " failed",
          category   = "test",
          fields     = { test_path = c.path },
          tags       = c.tags,
          evidence   = { { start_line = c.line, end_line = c.line } },
        })
      end
    end
  end
  return out
end
