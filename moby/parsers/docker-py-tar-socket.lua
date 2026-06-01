-- docker-py-tar-socket: dockerd's overlay2 graphdriver tries to tar up
-- a container's diff layer and hits a leftover UNIX socket file:
--   Can't add file /var/lib/docker/overlay2/<id>/diff/root/.gnupg/S.gpg-agent to tar: archive/tar: sockets not supported
-- gpg-agent doesn't clean up its socket between docker-py test runs,
-- so tar export fails. Job-level — no specific test to attribute (the
-- error fires inside dockerd's image-export code).

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("archive/tar: sockets not supported") then
      return {
        unique_key = "docker-py-tar-socket",
        name       = "dockerd image export: tar can't handle leftover UNIX socket",
        category   = "other",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
