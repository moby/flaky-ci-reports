-- docker-resolve-source-failed: buildx bake reports
--   buildx bake failed with: ERROR: failed to solve: failed to resolve source metadata for <image>: <inner error>
-- when BuildKit can't fetch source-image metadata from a registry.
-- The <image> is the cause shape — different upstream images failing
-- are different causes. Inner error (timeout, connection reset, HTTP
-- status) is recorded as a field but not in the key.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local image, inner = line:match(
      'buildx bake failed with: ERROR: failed to solve: failed to resolve source metadata for ([^:]+:[^:]+): (.+)$')
    if image then
      return {
        unique_key = "docker-resolve-source-failed:" .. image,
        name       = "Resolve source metadata failed: " .. image,
        category   = "network",
        fields     = { image = image, inner_error = inner },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
