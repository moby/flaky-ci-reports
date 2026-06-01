-- gh-cli-error: the GitHub CLI prints
--   gh: <message> (HTTP <status>)
-- when an API call fails. The status code identifies the failure mode
-- (403 = permission, 404 = missing resource, 5xx = server). The message
-- is human-readable but variable, so we key on status alone.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)delete artifacts" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local msg, status = line:match("gh: (.-) %(HTTP (%d+)%)")
    if status then
      return {
        unique_key = "gh-cli-error:" .. status,
        name       = "gh CLI HTTP " .. status .. ": " .. msg,
        category   = "network",
        fields     = { http_status = status, message = msg },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
