-- windows-daemon-not-ready: the Windows runner failed to bring the
-- docker daemon up before the test or build step needed it. Two
-- surfaces, one root cause:
--
--   (a) PS-poll throw — a helper script polls `docker info` and gives
--       up after N tries:
--          failed to connect to the docker API at npipe:////./pipe/docker_engine; ...
--          [...repeats...]
--          Exception: D:\a\_temp\<...>.ps1:11
--               Line | 11 | if ($tries -le 0) { throw "Docker daemon did not become ready" }
--                    |     Docker daemon did not become ready
--          ##[error]Process completed with exit code 1.
--
--   (b) direct-invocation form — a step runs `docker info` directly
--       (no polling helper) and dies on the first npipe failure:
--          Client: <details>
--          failed to connect to the docker API at npipe:////./pipe/docker_engine; ...
--          Server:
--          ##[error]Process completed with exit code 1.
--
-- Both unify under `windows-daemon-not-ready`. Trigger on either the
-- explicit `Docker daemon did not become ready` throw, or on the npipe
-- failure followed within a few lines by `##[error]Process completed
-- with exit code 1.` — bounding the gap avoids matching transient
-- mid-poll npipe noise in jobs where the daemon eventually came up.

-- No failed_steps gate: authoritative daemon-readiness cause — the real failure
-- wherever the daemon was needed. Reparse spans Docker info / Build base image /
-- Building contrib/busybox / Upload artifacts / Test.

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    -- (a) PS-throw — unambiguous.
    if line:match('Docker daemon did not become ready') then
      return {
        unique_key = "windows-daemon-not-ready",
        name       = "Windows docker daemon did not become ready",
        category   = "dependency",
        fields     = { variant = "ps-throw" },
        evidence   = { { start_line = i, end_line = i } },
      }
    end

    -- (b) npipe failure followed by exit-code-1 within 10 lines.
    if line:match("failed to connect to the docker API at npipe:////%./pipe/docker_engine") then
      for j = i + 1, math.min(i + 10, #log.lines) do
        if log.lines[j]:match("##%[error%]Process completed with exit code 1%.") then
          return {
            unique_key = "windows-daemon-not-ready",
            name       = "Windows docker daemon did not become ready",
            category   = "dependency",
            fields     = { variant = "direct-invocation" },
            evidence   = { { start_line = i, end_line = j } },
          }
        end
      end
    end
  end
  return nil
end
