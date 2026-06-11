-- freebsd-pkg-update-failed: the FreeBSD test path provisions its VM via
-- vagrant, and the `init (shell)` provisioner runs `pkg install -y git runj`.
-- The CI rewrites the pkg repo branch (`sed s/latest/release_2/`), and the
-- mirror then serves Not Found for every catalogue file under that branch:
--   pkg: https://pkgmir.geo.freebsd.org/FreeBSD:14:amd64/release_2/meta.txz: Not Found
--   ...
--   Unable to update repository FreeBSD
--   Error updating repositories!
-- pkg aborts non-zero, vagrant reports the SSH command failed, and the
-- "Set up vagrant" step fails. This is a broken package mirror / CI repo
-- config, not project code -> dependency.
--
-- Job-level: there is one FreeBSD pkg repo, so no per-run discriminator in
-- the key (the mirror host + branch are volatile context, kept in fields).
-- The job's other failed steps (BuildKit logs / Containerd logs, both just
-- `cat: ... No such file`) are downstream of the VM never being provisioned.

-- failed_steps: only fire when the vagrant setup step is the one that failed.
failed_steps = { "(?i)vagrant" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local repo = line:match("Unable to update repository (%S+)")
    if repo then
      -- Pull the mirror host + branch from a nearby pkg Not Found line for
      -- context (best-effort; not part of the key).
      local host, branch
      for j = math.max(1, i - 12), i do
        local h, b = log.lines[j]:match(
          "pkg: https?://([^/]+)/[^/]+/([%w_]+)/[^:]*: Not Found")
        if h then host, branch = h, b end
      end
      return {
        unique_key = "freebsd-pkg-update-failed",
        name       = "FreeBSD pkg: unable to update repository " .. repo,
        category   = "dependency",
        fields     = { repo = repo, mirror = host, branch = branch },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
