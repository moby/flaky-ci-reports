-- cosign-sign-failed: the docker-actions-toolkit's image-build signing step
-- runs `cosign sign ...` and, on failure, prints
--   Error: Signing BuildKit attestation manifests failed: Cosign sign command failed with errors:
--   - [<REASON>] <message> : null
-- The bracketed REASON token (UNAUTHORIZED, FAILED_PRECONDITION, etc.)
-- identifies the failure mode — auth/registry/sigstore each surface as
-- a different reason — and groups failures by their actual cause. The
-- exit code and downstream "Unhandled error" annotation are downstream
-- noise and aren't keyed on.
--
-- The umbrella line repeats in the same log (plain Error + ##[error]
-- Unhandled error wrapper), so we stop after the first match.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)sign" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("Cosign sign command failed with errors:") then
      for j = i + 1, math.min(i + 5, #log.lines) do
        local reason, msg = log.lines[j]:match("^[^Z]*Z%s*%-%s*%[(%S+)%]%s*(.-)%s*:%s*null%s*$")
        if not reason then
          reason, msg = log.lines[j]:match("^%-%s*%[(%S+)%]%s*(.-)%s*:%s*null%s*$")
        end
        if reason then
          return {
            unique_key = "cosign-sign-failed:" .. reason,
            name       = "cosign sign failed: " .. reason,
            category   = "network",
            fields     = { reason = reason, message = msg },
            evidence   = { { start_line = i, end_line = j } },
          }
        end
      end
      return {
        unique_key = "cosign-sign-failed",
        name       = "cosign sign failed",
        category   = "network",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
