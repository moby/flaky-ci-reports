-- github-artifact-upload-failed: actions/upload-artifact fails during
-- the Azure-backed blob upload. Two surface variants under one cause
-- family (upstream is typically a transient Azure blob storage 5xx):
--
--   server-busy: the action prints an explicit error
--     ##[error]The server is busy.
--     RequestId:<id>
--     Time:<ts>
--
--   silent: the action validates inputs, then dies before any upload
--   line appears. Detected as
--     Root directory input is valid!
--     <within a few lines>
--     Post job cleanup.
--   with no `Uploading artifact:` in between. This is what GH Actions
--   surfaces as "Upload test reports" failed without any error in the
--   captured log.
--
--   silent-finalize: the blob upload completes (`Finished uploading ...
--   blob storage!`) and the action reaches `Finalizing artifact upload`,
--   then dies before `successfully finalized` — straight to `Post job
--   cleanup.` with no error logged. Distinct phase from `silent` (which
--   dies *before* `Uploading artifact:`); here the finalize API call to
--   GitHub's artifact service is the one that silently fails.
--
-- One parser, several sub-keys, so reports can distinguish where in the
-- upload the action died and whether an error was emitted or swallowed.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)upload" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("##%[error%]The server is busy%.") then
      return {
        unique_key = "github-artifact-upload-failed:server-busy",
        name       = "actions/upload-artifact: Azure storage server busy",
        category   = "network",
        fields     = { variant = "server-busy" },
        evidence   = { { start_line = i, end_line = i } },
      }
    end

    if line:match("Root directory input is valid!") then
      local saw_upload = false
      local cleanup_line = nil
      for j = i + 1, math.min(i + 5, #log.lines) do
        if log.lines[j]:match("Uploading artifact:") then
          saw_upload = true
          break
        end
        if log.lines[j]:match("Post job cleanup%.") then
          cleanup_line = j
          break
        end
      end
      if cleanup_line and not saw_upload then
        return {
          unique_key = "github-artifact-upload-failed:silent",
          name       = "actions/upload-artifact: died before upload (no error logged)",
          category   = "network",
          fields     = { variant = "silent" },
          evidence   = { { start_line = i, end_line = cleanup_line } },
        }
      end
    end

    if line:match("Finalizing artifact upload") then
      local saw_finalized = false
      local cleanup_line = nil
      for j = i + 1, math.min(i + 3, #log.lines) do
        if log.lines[j]:match("successfully finalized")
            or log.lines[j]:match("has been successfully uploaded") then
          saw_finalized = true
          break
        end
        if log.lines[j]:match("Post job cleanup%.") then
          cleanup_line = j
          break
        end
      end
      if cleanup_line and not saw_finalized then
        return {
          unique_key = "github-artifact-upload-failed:silent-finalize",
          name       = "actions/upload-artifact: died during finalize (no error logged)",
          category   = "network",
          fields     = { variant = "silent-finalize" },
          evidence   = { { start_line = i, end_line = cleanup_line } },
        }
      end
    end
  end
  return nil
end
