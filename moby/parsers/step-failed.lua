-- step-failed: last-resort classifier driven by GitHub Actions step
-- metadata (ctx.failing_steps), not log content. Fires on jobs where:
--   1. No log-based parser produced an observation (fallback = true).
--   2. At least one step in the job has conclusion = "failure".
--   3. The failing step is on the curated `known` list below.
--
-- The curated list is critical. Without it, this parser auto-classifies
-- every novel failure pattern as `step-failed:<some-slug>` and hides the
-- "I need to write a real parser" signal — defeating the purpose of the
-- unknown bucket. Add a step name here only after you've decided that
-- failures of that step are noise (not flakes worth investigating).
--
-- Cancellations (conclusion = "cancelled") are intentionally NOT emitted
-- — cancelled steps are cascading effects per DESIGN.md §Parsers, never
-- the root cause.
--
-- Key shape: `step-failed:<slug>` (step name lowercased, non-alphanumerics
-- collapsed to `-`). Different failing-step families group separately in
-- reports.

fallback = true

local known = {
  -- Curated list of step names that are well-understood noise — cleanup
  -- cascades, infrastructure flakes, upstream-input failures. Edit as new
  -- step-level noise patterns are confirmed.
  ["Download Moby artifacts"]      = true,
  ["Download artifacts"]           = true,
  ["Upload reports"]               = true,
  ["Set up Go"]                    = true,
  -- Cleanup-only steps at the end of integration jobs: when these fail,
  -- the test itself already ran, and the failure is an unrelated
  -- post-test infrastructure hiccup.
  ["Stop OpenTelemetry Collector"] = true,
}

function parse(log, ctx)
  local out = {}
  local seen = {}
  for _, s in ipairs(ctx.failing_steps or {}) do
    if s.conclusion == "failure" and known[s.name] then
      local slug = s.name:gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""):lower()
      if slug ~= "" and not seen[slug] then
        seen[slug] = true
        table.insert(out, {
          unique_key = "step-failed:" .. slug,
          name       = "step '" .. s.name .. "' failed",
          category   = "other",
          fields     = { step_name = s.name },
          evidence   = {},
        })
      end
    end
  end
  return out
end
