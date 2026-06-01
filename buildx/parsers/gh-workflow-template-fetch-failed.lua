-- gh-workflow-template-fetch-failed: the Actions runner can't load a
-- reusable workflow (e.g. `docker/github-builder/.github/workflows/bake.yml@<sha>`)
-- because the upstream HTTP fetch failed. The downstream symptom is
-- always the same — the runner tried to JSON-parse a non-JSON body —
-- and surfaces as
--   ##[error]The template is not valid. <workflow>@<sha> (Line: ..., Col: ...): Error reading JToken from JsonReader. ...
--
-- Three variants distinguished by what (if anything) preceded the
-- template-not-valid line *anywhere earlier in the same log*:
--
--   (a) `##[error][Unhandled error: Error: ]Unexpected HTTP response: <CODE>`
--       → gh-workflow-template-fetch-failed:<status>
--
--   (b) `##[error]<!DOCTYPE html>` (followed by an inline HTML error
--       page — the body bleeds across many lines until the template
--       line; we don't bound the gap)
--       → gh-workflow-template-fetch-failed:html
--
--   (c) neither — cause not surfaced to the log.
--       → gh-workflow-template-fetch-failed:unknown
--
-- Single-pass: record the most recent http-status / html-body marker;
-- when we hit `The template is not valid`, classify from state.

-- No failed_steps gate: authoritative upstream-fetch cause — the reusable workflow
-- could not be loaded (HTTP 500 / HTML body). Reparse spans Docker meta / Build /
-- Set up Buildx / Validate. Categorized as network (see returns below).

function parse(log, ctx)
  local saw_status = nil
  local saw_status_line = nil
  local saw_html = false
  local saw_html_line = nil

  for i, line in ipairs(log.lines) do
    do
      local status = line:match("##%[error%].*Unexpected HTTP response: (%d+)")
      if status then
        saw_status = status
        saw_status_line = i
      end
    end
    if line:match("##%[error%]<!DOCTYPE html>") then
      saw_html = true
      saw_html_line = i
    end

    if line:match("The template is not valid") then
      if saw_status then
        return {
          unique_key = "gh-workflow-template-fetch-failed:" .. saw_status,
          name       = "GitHub workflow template fetch failed: HTTP " .. saw_status,
          category   = "network",
          fields     = { status = saw_status, variant = "http" },
          evidence   = { { start_line = saw_status_line, end_line = i } },
        }
      end
      if saw_html then
        return {
          unique_key = "gh-workflow-template-fetch-failed:html",
          name       = "GitHub workflow template fetch failed: HTML error body",
          category   = "network",
          fields     = { variant = "html" },
          evidence   = { { start_line = saw_html_line, end_line = i } },
        }
      end
      return {
        unique_key = "gh-workflow-template-fetch-failed:unknown",
        name       = "GitHub workflow template fetch failed: cause not in log",
        category   = "network",
        fields     = { variant = "unknown" },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
