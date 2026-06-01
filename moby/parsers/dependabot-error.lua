-- dependabot-error: the Dependabot updater action prints a summary table
-- of failed jobs:
--   updater | ... INFO Results:
--   Dependabot encountered '<N>' error(s) during execution, please check the logs for more details.
--   +---...---+
--   | Errors  ...
--   | Type            | Details ...
--   | <error_type>    | { ...
--   |                 |   "branch-name": ...,
--   |                 |   "message": ...
--   ...
--   ##[error]Dependabot encountered an error performing the update
--
-- The Type column value (`branch_not_found`, `private_source_authentication_failure`,
-- `runner_error`, ...) is the cause shape. Distinct types indicate
-- distinct root causes worth tracking separately.
--
-- The umbrella `##[error]Dependabot encountered an error performing the
-- update` line is generic — we only fire when we've actually extracted
-- a type from the inner table.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)dependabot" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("Dependabot encountered '%d+' error%(s%) during execution") then
      -- Walk forward looking for the first row of the errors table.
      -- The first `| <type> | { ... ` line within ~30 lines is the type
      -- column entry; subsequent lines are the details payload.
      for j = i + 1, math.min(i + 30, #log.lines) do
        local etype = log.lines[j]:match("^[^Z]*Z |%s+([%w_]+)%s+|%s*{")
        if etype then
          return {
            unique_key = "dependabot-error:" .. etype,
            name       = "Dependabot error: " .. etype,
            category   = "dependency",
            fields     = { error_type = etype },
            evidence   = { { start_line = i, end_line = j } },
          }
        end
      end
      -- Fallback: umbrella matched but inner type couldn't be parsed.
      return {
        unique_key = "dependabot-error",
        name       = "Dependabot encountered an error (type not parsed)",
        category   = "dependency",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
