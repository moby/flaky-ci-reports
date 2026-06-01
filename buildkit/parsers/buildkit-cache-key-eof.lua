-- buildkit-cache-key-eof: BuildKit fails to compute a cache key when
-- an upstream image fetch was cancelled mid-stream, producing
--   ERROR: failed to solve: failed to compute cache key: short read: expected <N> bytes but got 0: unexpected EOF
--
-- Underlying cause is usually a `context canceled` on a `Get
-- "https://<upstream>/v2/.../blobs/sha256:..."` from buildkitd's
-- debug logs — but only the outer "short read EOF" makes it into the
-- bake umbrella. Single key for now; if we start seeing distinct
-- upstreams worth grouping by, key on the host from the debug logs.
--
-- Distinct from gha-cache-export-error which is the GHA cache backend
-- returning 5xx during *export*. This is *import* / source fetch.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("failed to compute cache key: short read: expected %d+ bytes but got 0: unexpected EOF") then
      return {
        unique_key = "buildkit-cache-key-eof",
        name       = "BuildKit cache key compute failed: short read EOF",
        category   = "other",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
