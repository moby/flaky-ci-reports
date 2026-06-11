-- buildx-driver-bootstrap-failed: the `driver` integration test runs
-- `make test-driver` -> `./hack/test-driver`, which first does
--   docker buildx create --bootstrap --driver=kubernetes ...
-- to boot a BuildKit instance. With the kubernetes driver this waits for the
-- BuildKit pod to become ready and times out:
--   #1 waiting for 1 pods to be ready, timeout: 2 minutes 120.2s done
--   #1 ERROR: expected 1 replicas to be ready, got 0
--   ERROR: expected 1 replicas to be ready, got 0
-- and `make` then exits non-zero (`make: *** [Makefile:..] Error 1` ->
-- `##[error]Process completed with exit code 2.`). The exit code is not the
-- cause — the BuildKit pod never coming up is. Infra/readiness flake ->
-- dependency.
--
-- Tags carry the matrix dims (driver + multi-node) pulled from the step env,
-- so reports can tell whether the readiness failure clusters on a particular
-- driver config (e.g. multi-node) rather than being a uniform flake.

-- failed_steps: only fire when the Test step is the one that failed.
failed_steps = { "(?i)test" }

function parse(log, ctx)
  -- Pre-scan the step env dump for the matrix dims (they appear once, before
  -- the error).
  local driver, mnode
  for _, line in ipairs(log.lines) do
    driver = driver or line:match("^%s*[%d:.TZ-]*%s*DRIVER:%s*(%S+)")
    local mn = line:match("^%s*[%d:.TZ-]*%s*MULTI_NODE:%s*(%d+)")
    if mn then mnode = (mn == "1") and "true" or "false" end
    if driver and mnode then break end
  end

  for i, line in ipairs(log.lines) do
    local got = line:match("ERROR: expected %d+ replicas to be ready, got (%d+)")
    if got then
      local tags = {}
      if driver then tags.driver = driver end
      if mnode then tags.mnode = mnode end
      return {
        unique_key = "buildx-driver-bootstrap-failed:replicas-not-ready",
        name       = "buildx driver bootstrap: BuildKit pod never became ready",
        category   = "dependency",
        fields     = { driver = driver, mnode = mnode, replicas_ready = got },
        tags       = tags,
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
