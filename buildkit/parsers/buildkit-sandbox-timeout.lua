-- buildkit-sandbox-timeout: BuildKit's integration-test sandbox emits
--   sandbox.go:147: sandbox timeout reached, stopping worker
-- when a test (or chain of tests sharing the sandbox) exceeds the
-- configured timeout. The test that was running when the timeout fired
-- becomes a tag; multiple tests timing out across attempts group together
-- as one cause.
--
-- Overrides the whole test-failure cause-family: once the sandbox times out,
-- every other test sharing it cascades — failing either as a plain test FAIL
-- (go-test-failure) or with connection/registry errors from the now-dead worker
-- (registry-net-error / registry-error / docker-daemon-error). All of those are
-- symptoms; the sandbox timeout is the one real cause for the job.
overrides = { "go-test-failure", "registry-net-error", "registry-error", "docker-daemon-error" }

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    if line:match("sandbox%.go:%d+: sandbox timeout reached, stopping worker") then
      local test_path = failing_test_near(log, i, 2000)
      local test_tags = {}
      local bare = nil
      if test_path then
        bare, test_tags = extract_tags(test_path, {"worker", "frontend", "slice"})
        if bare == "TestIntegration" or bare == "" then
          bare = nil
        end
      end
      local tags = test_tags
      if bare then tags.test = bare end

      local dedup_key = bare or ""
      if not seen[dedup_key] then
        seen[dedup_key] = true
        table.insert(out, {
          unique_key = "buildkit-sandbox-timeout",
          name       = "BuildKit sandbox timeout",
          category   = "other",
          fields     = {},
          tags       = tags,
          evidence   = { { start_line = i, end_line = i } },
        })
      end
    end
  end
  return out
end
