-- npm-error: npm prints
--   npm error code <CODE>
-- (e.g., ECONNRESET, ENOENT, E404) and then exits non-zero. The error
-- code identifies the failure mode — ECONNRESET = network issue against
-- the registry, ENOENT = missing package, E404 = package not found, etc.
-- — and groups failures by their actual cause.
--
-- The downstream "process '/usr/local/bin/npm' failed with exit code N"
-- (and the `##[error]Unhandled error: ...` wrapper) is just exit-code
-- noise and isn't keyed on.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)install" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local code = line:match("^[^Z]*Z npm error code (%S+)$")
    if code then
      return {
        unique_key = "npm-error:" .. code,
        name       = "npm error " .. code,
        category   = "dependency",
        fields     = { error_code = code },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
