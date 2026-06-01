-- provenance-sign-failed: docker-actions-toolkit's signProvenanceBlobs
-- path (direct sigstore lib, not the cosign CLI wrapper) prints
--   Error: Signing BuildKit provenance blobs failed: <reason>
-- The <reason> is short and inline (e.g. "error retrieving identity
-- token" when sigstore's OIDC dance fails). Normalize it to a stable
-- key — sigstore-side failure modes are the cause family.
--
-- The umbrella repeats as `##[error]Unhandled error: ...` a few lines
-- later; returning on the first match avoids double-counting.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)sign" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local reason = line:match("Error: Signing BuildKit provenance blobs failed: (.+)$")
    if reason then
      local token = normalize(reason):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
      return {
        unique_key = "provenance-sign-failed:" .. token,
        name       = "Provenance signing failed: " .. reason,
        category   = "network",
        fields     = { reason = reason },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
