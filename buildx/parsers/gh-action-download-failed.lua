-- gh-action-download-failed: the Actions runner tries to download an
-- action tarball from api.github.com (or codeload.github.com) and the
-- HTTP request keeps coming back non-2xx. Retried with backoff;
-- eventually fails with
--   ##[warning]Failed to download action 'https://<host>/...'. Error: Response status code does not indicate success: <CODE> (<reason>). <id>
--   ##[warning]Back off N seconds before retry.
--   [...repeat...]
--   ##[error]Response status code does not indicate success: <CODE> (<reason>).
--
-- Status code identifies the failure mode (401 = token problem,
-- 403 = permission, 429 = rate limit, 5xx = upstream flake). The
-- download host varies (api.github.com vs codeload.github.com) but
-- is not in the key — it's the same cause family.
--
-- The `##[error]Response status code...` line is generic .NET HTTP
-- client text and could appear in non-action-download contexts;
-- require a preceding `Failed to download action` warning in the same
-- log to confirm.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)set up job" }

function parse(log, ctx)
  local saw_download_warning = false
  for i, line in ipairs(log.lines) do
    if line:match("Failed to download action") then
      saw_download_warning = true
    end
    local status = line:match("##%[error%]Response status code does not indicate success: (%d+)")
    if status and saw_download_warning then
      return {
        unique_key = "gh-action-download-failed:" .. status,
        name       = "GitHub action download failed: HTTP " .. status,
        category   = "network",
        fields     = { status = status },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
