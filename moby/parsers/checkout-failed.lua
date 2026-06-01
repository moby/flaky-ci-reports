-- checkout-failed: the actions/checkout step prints
--   ##[group]Fetching the repository
--   [command]/.../git ... fetch ... origin +refs/heads/<REF>*:refs/remotes/origin/<REF>* ...
--   The process '/.../git' failed with exit code 1
--   Waiting N seconds before trying again
--   [...retries...]
--   ##[error]The process '/.../git' failed with exit code 1
-- when the action can't fetch the configured ref. The ref pattern is
-- the cause shape — moby hits this when a templated `ref:` input
-- resolves to literal "null" (CI variable not set), but it could also
-- be a transient github.com hiccup against a real ref.
--
-- Different ref patterns group separately: `checkout-failed:null` is
-- the broken-template case; `checkout-failed:<sha-prefix>` would be a
-- transient network/permission issue against a real ref.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)checkout" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    -- Look for the fetch command line; capture the ref pattern.
    local ref = line:match(
      "fetch %-%-no%-tags %-%-prune %-%-no%-recurse%-submodules %-%-depth=%d+ origin %+refs/heads/(%S+)%*:")
    if not ref then
      goto continue
    end
    -- Confirm this is a checkout-step failure (look forward for the
    -- terminal ##[error] git-failed line). Without that, the line is
    -- just a successful fetch.
    for j = i + 1, math.min(i + 60, #log.lines) do
      if log.lines[j]:match("##%[error%]The process.*git.*failed with exit code") then
        return {
          unique_key = "checkout-failed:" .. ref,
          name       = "actions/checkout: git fetch failed for ref '" .. ref .. "'",
          category   = "other",
          fields     = { ref_pattern = ref },
          evidence   = { { start_line = i, end_line = j } },
        }
      end
    end
    ::continue::
  end
  return nil
end
