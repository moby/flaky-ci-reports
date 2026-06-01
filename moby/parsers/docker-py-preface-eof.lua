-- docker-py-preface-eof: dockerd's http2 server logs
--   http2: server: error reading preface from client @: read unix /run/docker/tmp.<rand>/docker.sock->@: read: connection reset by peer
-- when a Python docker-py client connection died mid-handshake before
-- the HTTP/2 preface completed. Hit in test (graphdriver) / docker-py
-- and test (snapshotter) / docker-py jobs when the test suite races a
-- container teardown and the socket goes away. Job-level — there is no
-- specific test to attribute (multiple tests may race in parallel).

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)test" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("http2: server: error reading preface from client.*: read: connection reset by peer") then
      return {
        unique_key = "docker-py-preface-eof",
        name       = "docker-py: dockerd http2 preface reset by client",
        category   = "other",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
