-- docker-push-failed: image push to a registry failed. Two shapes:
--
--   (a) bake form:
--      buildx bake failed with: ERROR: failed to solve: failed to push <image>: <reason>
--      e.g. `failed to push moby/moby-bin: unknown: blob upload unknown to registry - blob upload unknown`
--      → docker-push-failed:<image>:<reason-token>
--
--   (b) toolkit-wrapper form (buildx bin-image finalize step):
--      Error: #<N> [internal] pushing <image>
--      (no further detail in the log)
--      → docker-push-failed:<image>
--
-- The image is the cause shape. Reason token normalized when available
-- so e.g. `blob upload unknown` collapses across runs.

-- No failed_steps gate: authoritative image-push cause — the "[internal] pushing"
-- / "failed to push" line only appears on a real push failure.

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    -- (a) bake form
    do
      local image, reason = line:match(
        'buildx bake failed with: ERROR: failed to solve: failed to push (%S+): (.+)$')
      if image then
        local token = reason:gsub("%s+", "-"):gsub("[^%w%-]+", "-")
                            :gsub("^%-+", ""):gsub("%-+$", ""):lower()
        -- Truncate to keep the key bounded.
        if #token > 60 then token = token:sub(1, 60) end
        return {
          unique_key = "docker-push-failed:" .. image .. ":" .. token,
          name       = "docker push " .. image .. " failed: " .. reason,
          category   = "network",
          fields     = { image = image, reason = reason },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end

    -- (b) toolkit-wrapper form
    do
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
  end
  return nil
end
