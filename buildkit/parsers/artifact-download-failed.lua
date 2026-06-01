-- artifact-download-failed: actions/download-artifact fails to fetch a
-- build artifact a downstream job depends on. The runner prints
--   ##[error]Unable to download artifact(s): <reason>
-- Two reason families seen, keyed separately because they're different causes:
--
--   not-found  — `Artifact not found for name: <name>`
--                the upstream job never produced it (a missing dependency).
--   timeout    — `Failed to ListArtifacts: Unable to make request: ETIMEDOUT`
--                (or other transport error) — a network flake reaching the
--                artifacts service.
--
-- failed_steps gate: only fire when a "Download artifacts" step is the one that
-- failed — the line is authoritative, but gating keeps it from matching a stray
-- mention elsewhere.

failed_steps = { "(?i)download artifacts" }

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
        key, cat = "error", "other"
        name = "Download artifact failed"
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
