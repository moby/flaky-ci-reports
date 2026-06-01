-- docker-pull-blocked: legacy docker pull reports
--   pull access denied for <host>/<repo>, repository does not exist or may require 'docker login': denied: <!DOCTYPE html ...>...The request is blocked.</h2>...
-- when the registry returns an HTML "blocked" page instead of a proper
-- auth challenge. Hit on mcr.microsoft.com fetching Windows base
-- images; the registry intermittently blocks anonymous requests from
-- specific edge nodes.
--
-- Distinct from registry-error.lua (BuildKit-style "unexpected status
-- from <OP> request to ...: <CODE>"). Shares the `registry-error:`
-- namespace so reports group both into the same family.
--
-- Overrides go-test-failure: when the registry blocks a docker pull
-- that a test depends on, the test FAIL is downstream noise.

overrides = { "go-test-failure" }

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local host = line:match(
      "pull access denied for ([^/]+)/[^,]+, repository does not exist or may require 'docker login': denied: <!DOCTYPE html")
    if host then
      return {
        unique_key = "registry-error:" .. host .. ":blocked",
        name       = "Registry " .. host .. " returned blocked HTML body",
        category   = "network",
        fields     = { host = host, reason = "blocked" },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
