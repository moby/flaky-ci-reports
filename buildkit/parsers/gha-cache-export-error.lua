-- gha-cache-export-error: GitHub Actions Cache backend returns 5xx
-- while BuildKit is `exporting to GitHub Actions Cache`. BuildKit prints
--   #NN ERROR: error writing layer blob: failed to parse error response <CODE>: <html>
-- (the response body is the raw GitHub error page, which can include a
-- base64-encoded inline PNG; that whole blob ends up inside the
-- `##[error]buildx bake failed with: ...` umbrella, which is why the
-- wider buildx-bake-build-failed parser misses these.)
--
-- The status code is the cause shape — different cache backend errors
-- (502 Bad Gateway, 503 Unavailable) are different transient flakes.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local status = line:match("error writing layer blob: failed to parse error response (%d+):")
    if status then
      return {
        unique_key = "gha-cache-export-error:" .. status,
        name       = "GHA cache export: backend returned HTTP " .. status,
        category   = "network",
        fields     = { status = status },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
