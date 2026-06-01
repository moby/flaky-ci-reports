-- docker-push-failed: the bin-image finalize step pushes the built
-- binary image to docker.io and on failure prints only
--   Error: #<N> [internal] pushing <image>
--   ##[error]Unhandled error: Error: #<N> [internal] pushing <image>
-- with no further detail surfaced to the log (the underlying registry
-- error is swallowed by the toolkit wrapper). The image being pushed
-- is the cause shape; without an inner reason, we key on image alone.

-- No failed_steps gate: authoritative image-push cause — the "[internal] pushing"
-- / "failed to push" line only appears on a real push failure.

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local image = line:match("^[^Z]*Z Error: #%d+ %[internal%] pushing (%S+)%s*$")
    if image then
      return {
        unique_key = "docker-push-failed:" .. image,
        name       = "docker push failed: " .. image,
        category   = "network",
        fields     = { image = image },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
