-- gh-action-download-failed: the Actions runner can't fetch an action's
-- tarball from GitHub. Two surface variants:
--
--   (a) Multi-attempt with HTTP status:
--      ##[warning]Failed to download action 'https://.../tarball/<sha>'. Error: Response status code does not indicate success: <CODE> (<reason>). <id>
--      ##[warning]Back off N seconds before retry.
--      [...repeat 2-3x...]
--      ##[error]Response status code does not indicate success: <CODE> (<reason>).
--      → gh-action-download-failed:<status>
--
--   (b) Single-attempt "not found":
--      ##[error]An action could not be found at the URI 'https://.../tar.gz/<sha>' (<id>)
--      ##[error]Failed to download archive '...' after N attempts.
--      → gh-action-download-failed:not-found
--
-- The `##[error]Response status code...` line is generic .NET HTTP
-- client text; require a preceding `Failed to download action` warning
-- in the same log to confirm variant (a). Variant (b)'s `An action
-- could not be found at the URI` line is specific enough to fire alone.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)set up job" }

function parse(log, ctx)
  local saw_download_warning = false
  for i, line in ipairs(log.lines) do
    -- (b) not-found variant — specific enough to match alone.
    do
      local url = line:match("##%[error%]An action could not be found at the URI '([^']+)'")
      if url then
        return {
          unique_key = "gh-action-download-failed:not-found",
          name       = "GitHub action not found at URI",
          category   = "network",
          fields     = { url = url, variant = "not-found" },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end

    if line:match("Failed to download action") then
      saw_download_warning = true
    end
    local status = line:match("##%[error%]Response status code does not indicate success: (%d+)")
    if status and saw_download_warning then
      return {
        unique_key = "gh-action-download-failed:" .. status,
        name       = "GitHub action download failed: HTTP " .. status,
        category   = "network",
        fields     = { status = status, variant = "http" },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
