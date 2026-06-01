-- git-fetch-connect-failed: git reports
--   fatal: unable to access '<url>': Failed to connect to <host> port <port> after <ms> ms: Could not connect to server
-- when the network layer can't establish a TCP connection to the git
-- remote (typically inside BuildKit's `RUN --mount=type=ssh` or a
-- bake stage doing `go mod download`). The host + port identify the
-- failure shape; the millisecond budget is dropped.
--
-- Distinct from git-fetch-no-credentials (which is auth, not
-- connectivity). The downstream symptom is a buildx bake error
-- whose inner exit-code-1 process is the script that ran the git
-- command — buildx-bake-build-failed would catch that wrapper, but
-- this parser names the actual root cause.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local url, host, port = line:match(
      "fatal: unable to access '([^']+)': Failed to connect to (%S+) port (%d+)")
    if url then
      return {
        unique_key = "git-fetch-connect-failed:" .. host .. ":" .. port,
        name       = "git fetch failed: cannot connect to " .. host .. ":" .. port,
        category   = "network",
        fields     = { url = url, host = host, port = port },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
