-- attestation-sign-fetch-failed: docker-actions-toolkit's
-- signAttestationManifests path fails when it can't fetch a blob from
-- the registry while signing. Surfaces as
--   Error: Signing BuildKit attestation manifests failed: ERROR: failed to copy: httpReadSeeker: failed open: failed to do request: <OP> "https://<host>/<path>": <inner>
-- The <host> + <inner> reason identify the cause shape — a different
-- host or a different reason (EOF vs timeout vs connection-reset) is
-- a different transient registry flake.
--
-- Distinct from cosign-sign-failed (which fires on "Cosign sign command
-- failed with errors:" — cosign-CLI-side) and provenance-sign-failed
-- (which fires on "Signing BuildKit provenance blobs failed:" — the
-- provenance path, not attestation). The three sign-failure families
-- have distinct umbrellas; one parser per umbrella keeps them apart.
--
-- The umbrella repeats as `##[error]Unhandled error: ...` a few lines
-- later; returning on the first match avoids double-counting.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)sign" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("Signing BuildKit attestation manifests failed:") then
      -- Inner registry-fetch shape: `Get "https://<host>/<path>": <inner>`.
      local host, inner = line:match(
        'failed to do request: %S+ "https?://([^/"]+)[^"]*": (.+)$')
      if host then
        local token = inner:gsub("%s+", "-"):gsub("[^%w%-]+", "-")
                           :gsub("^%-+", ""):gsub("%-+$", ""):lower()
        return {
          unique_key = "attestation-sign-fetch-failed:" .. host .. ":" .. token,
          name       = "Attestation sign: fetch from " .. host .. " failed: " .. inner,
          category   = "network",
          fields     = { host = host, inner = inner },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
      -- Fallback: umbrella matched but inner shape unrecognized.
      return {
        unique_key = "attestation-sign-failed",
        name       = "Signing BuildKit attestation manifests failed",
        category   = "network",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
