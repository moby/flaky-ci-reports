-- gh-workflow-template-fetch-failed: the Actions runner can't load a
-- reusable workflow (e.g. `docker/github-builder/.github/workflows/bake.yml@<sha>`)
-- because the upstream HTTP fetch returns non-2xx. Surfaces as a pair:
--   ##[error][Unhandled error: Error: ]Unexpected HTTP response: <CODE>
--   ##[error]The template is not valid. <workflow>@<sha> (Line: ..., Col: ...): Error reading JToken from JsonReader. ...
--
-- The second line is the downstream symptom (the runner tried to JSON-
-- parse an empty/error response body); the HTTP status is the cause.
-- Require both lines for confirmation — `Unexpected HTTP response` is
-- a generic .NET HTTP message and could appear in other contexts.

-- DISABLED pending a log-based rewrite: `flakie parser steps` showed this
-- parser's matches were mis-attributed to unrelated failed steps. Gated to a
-- step that never exists, so its jobs fall through to "unknown" and can be
-- re-examined with logs via `flakie unknown export`.
failed_steps = { "flakie:disabled-pending-log-review" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local status = line:match("##%[error%].*Unexpected HTTP response: (%d+)")
    if status then
      for j = i + 1, math.min(i + 3, #log.lines) do
        if log.lines[j]:match("The template is not valid") then
          return {
            unique_key = "gh-workflow-template-fetch-failed:" .. status,
            name       = "GitHub workflow template fetch failed: HTTP " .. status,
            category   = "network",
            fields     = { status = status },
            evidence   = { { start_line = i, end_line = j } },
          }
        end
      end
    end
  end
  return nil
end
