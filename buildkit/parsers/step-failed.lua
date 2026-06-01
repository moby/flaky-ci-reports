-- step-failed: last-resort classifier driven by GitHub Actions step metadata
-- (ctx.failing_steps), not log content. Fires only when:
--   1. No log-based parser produced an observation (fallback = true), AND
--   2. A failing step's name is on the curated `known` list below.
--
-- The curated list is critical. Without it this auto-classifies every novel
-- failure as `step-failed:<slug>` and hides the "write a real parser" signal.
-- Only add a step here once its failures are confirmed noise with no better
-- log signal — e.g. the Windows jobs that fail at "Set up Go" / "Download
-- artifacts" leaving NO error in the captured log (runner-side failures).
--
-- Cancellations (conclusion = "cancelled") are intentionally NOT emitted —
-- cancelled steps are cascading effects per DESIGN.md §Parsers, never a cause.
--
-- Key shape: `step-failed:<slug>` (step name lowercased, non-alphanumerics
-- collapsed to `-`). Different failing-step families group separately.

fallback = true

local known = {
  -- Windows runner-side failures with no parseable log line (confirmed via
  -- `flakie unknown export`: 0 error annotations, failing step is the signal).
  ["Set up Go"]              = true,
  ["Download artifacts"]     = true,
  -- Setup steps whose only signal is a generic HTTP 5xx from an upstream
  -- service (cosign install / buildx setup) — network noise, no better key.
  ["Install Cosign"]         = true,
  ["Set up Docker Buildx"]   = true,
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
