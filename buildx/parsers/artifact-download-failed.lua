-- artifact-download-failed: actions/download-artifact fails to fetch a
-- build artifact a downstream job depends on. In buildx this surfaces inside
-- the "Install buildx" composite step (which downloads the buildx binary
-- artifact). The runner prints
--   ##[error]Unable to download artifact(s): <reason>
-- Reason families, keyed separately because they're different causes:
--
--   not-found  — `Artifact not found for name: <name>`
--                the upstream job never produced it (a missing dependency).
--   timeout    — `Failed to ListArtifacts: Unable to make request: ETIMEDOUT`
--                (or other transport error) — a network flake reaching the
--                artifacts service.
--   http-<code> — `Failed to ListArtifacts: Received non-retryable error:
--                Failed request: (<CODE>) <reason>: Error from intermediary ...`
--                the artifacts-service intermediary returned a non-2xx (e.g.
--                403) — a transient over-the-wire failure, not a real perm
--                problem (the job normally succeeds).
--
-- failed_steps gate: only fire when the buildx-install / artifact-download step
-- is the one that failed — the line is authoritative, but gating keeps it from
-- matching a stray mention elsewhere.

failed_steps = { "(?i)install buildx", "(?i)download artifact" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local reason = line:match("##%[error%]Unable to download artifact%(s%): (.+)$")
    if reason then
      local key, cat, name
      if reason:match("Artifact not found") then
        key, cat = "not-found", "dependency"
        name = "Download artifact: artifact not found"
      elseif reason:match("ETIMEDOUT") or reason:match("Unable to make request")
          or reason:match("timeout") or reason:match("ECONNRESET") then
        key, cat = "timeout", "network"
        name = "Download artifact: network error"
      else
        local status = reason:match("Failed request: %((%d+)%)")
        if status then
          key, cat = "http-" .. status, "network"
          name = "Download artifact: artifacts service returned HTTP " .. status
        else
          key, cat = "error", "other"
          name = "Download artifact failed"
        end
      end
      return {
        unique_key = "artifact-download-failed:" .. key,
        name       = name,
        category   = cat,
        fields     = { reason = reason },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
