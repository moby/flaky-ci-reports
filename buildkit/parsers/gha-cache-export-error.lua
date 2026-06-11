-- gha-cache-export-error: GitHub Actions Cache backend returns 5xx
-- while BuildKit is `exporting to GitHub Actions Cache`. Two surface shapes
-- under one cause family:
--
--   A. layer-blob write failure (BuildKit prints the raw GitHub error page):
--        #NN ERROR: error writing layer blob: failed to parse error response <CODE>: <html>
--      The response body can include a base64-encoded inline PNG; that whole
--      blob ends up inside the `##[error]buildx bake failed with: ...`
--      umbrella, which is why the wider buildx-bake-build-failed parser
--      misses these.
--
--   B. solve failure during cache export (the proxy fronting the cache
--      backend returns the 5xx, not the blob writer):
--        ERROR: failed to solve: failed to parse error response <CODE>: upstream connect error ...
--      Only attributed to the cache export when the log actually contains the
--      `exporting to GitHub Actions Cache` phase — otherwise a generic solve
--      failure would be mis-keyed here.
--
-- The status code is the cause shape — different cache backend errors
-- (502 Bad Gateway, 503 Unavailable) are different transient flakes.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build" }

function parse(log, ctx)
  local cache_export = log.text:find("exporting to GitHub Actions Cache") ~= nil

  for i, line in ipairs(log.lines) do
    -- A. layer-blob write failure (always a GHA cache export).
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

    -- B. solve failure, only when the cache-export phase is present.
    if cache_export then
      local status2 = line:match("failed to solve: failed to parse error response (%d+):")
      if status2 then
        return {
          unique_key = "gha-cache-export-error:" .. status2,
          name       = "GHA cache export: backend returned HTTP " .. status2,
          category   = "network",
          fields     = { status = status2 },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end
  end
  return nil
end
