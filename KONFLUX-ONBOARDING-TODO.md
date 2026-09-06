# Konflux hermetic onboarding — remaining work

Tracking the open items for onboarding **x2a-convertor** to Konflux as a
**Product** (hermetic build, gated by Enterprise Contract / Conforma).
Branch: `konflux-hermetic-onboarding`.

## Onboarding sequence (important — read before merging .tekton/)

The `.tekton/` PipelineRuns in this branch are **authored ahead of time and are
NOT the ones we ultimately run as-is**. The real flow is:

1. Open an MR in the **konflux-release-data** repo (tenant onboarding +
   Application/Component). This is what actually registers the component.
2. Creating the Component makes Konflux **open a PR against this convertor repo**
   that adds its own generated `.tekton/` PipelineRun files.
3. **Merge our `.tekton/` changes into that generated PR** — i.e. take Konflux's
   generated files and fold in our hermetic settings (`hermetic=true`,
   `build-source-image=true`, the 3-type `prefetch-input`, `build-platforms`
   x86_64). Our committed files here are the reference for that merge, not the
   final artifact.

So: commit + push our `.tekton/` files now, but expect to reconcile them against
the Konflux-generated PR rather than using them verbatim.

## Placeholders to replace

- [ ] **CPE** — `LABEL cpe=` in `Dockerfile` is a placeholder
      (`cpe:/a:redhat:x2a_convertor:1`). Replace with the ProdSec-assigned CPE.
      Must match the ReleasePlanAdmission `releaseNotes.cpe` **exactly** or the
      release gate fails.
- [ ] **version / release** — `LABEL version="0.1.0"` and `release="1"` in
      `Dockerfile` are hardcoded from pyproject. Decide the versioning scheme;
      most RH product pipelines inject these via build args/labels rather than
      static values. Convert to `ARG`-driven once decided.
- [ ] **`<TENANT_NAMESPACE>`** in both `.tekton/*.yaml` — set after the tenant
      namespace is created (add-namespace.sh MR).
- [ ] **output-image quay path** in `.tekton/*.yaml` — confirm the
      `quay.io/redhat-user-workloads/<TENANT_NAMESPACE>/x2a-convertor` path.
- [ ] **serviceAccountName** (`build-pipeline-x2a-convertor`) in `.tekton/*.yaml`
      — confirm against what Konflux generates for the component.

## External / team dependencies (long lead — request early)

- [ ] **CPE ID + product stream** from ProdSec (product-definitions MR /
      prodsec-request@redhat.com).
- [ ] **Errata Product ID** from Releng (ContainerReleng Jira /
      #forum-konflux-release).
- [ ] **konflux-release-data GitOps MRs**: ReleasePlan, ReleasePlanAdmission
      (rh-push-to-registry-redhat-io, dest registry.redhat.io, CPE in
      `.spec.data.releaseNotes`), constraints file, CODEOWNERS.

## Validate in the FIRST real hermetic Konflux build (iterate in the PR)

- [ ] **Bundler gem persistence** — confirm vendored gems land at
      `/app/vendor/bundle` and aren't installed into a `/cachi2` path that
      doesn't persist (cachi2.env may set `BUNDLE_CACHE_PATH` as the source;
      deployment mode should install into `vendor/bundle`).
- [ ] **Binstub cwd lookup** — `chef-cli` runs from `tempfile.mkdtemp()` and
      `r10k` from a module root (arbitrary cwd). Confirm the binstubs find the
      Gemfile/gems via global `BUNDLE_GEMFILE=/app/Gemfile`; fallback is
      `bundle binstubs --standalone`.
- [ ] **`uv run` offline** — confirm `uv run app.py` execs `/app/.venv` with
      `UV_NO_SYNC=1` and never re-resolves / hits the network, even though the
      venv wasn't created by uv.
- [ ] **Source RPMs / build-source-image** — `rpm-lockfile-prototype` warned
      "No sources found" for gcc/cmake/rubygems etc. May need source repos
      enabled in `rpms.in.yaml` for `build-source-image=true` to succeed.
- [ ] **Conforma binary-wheel violations** — expected (pydantic-core,
      cryptography, grpcio, tree-sitter, tokenizers, etc. are binary wheels).
      Do NOT pre-file an exception; let Conforma surface the exact PURLs, then
      file a targeted exception (or move those to from-source if few).

## Decisions to confirm in MR/PR review

- [ ] **Keeping `uv` in the image** (offline launcher) preserves the RHDH
      `uv run app.py` contract with zero cross-repo change, but adds one
      binary-provenance item to the Product image. Cleaner long-term option:
      drop `uv`, and change rhdh-plugins
      `workspaces/x2a/plugins/x2a-backend/templates/x2a-job-script.sh` from
      `uv run app.py` to `python3.14 app.py` (every phase, incl the
      `uv run --project /app` call).
- [ ] **x86_64 only** to start — revisit if the Product must ship aarch64
      (affects lockfile arches in `rpms.in.yaml` / `Gemfile.lock`).
- [ ] **python3.14** — ~3yr lifecycle vs 10yr for platform python3 (3.12).
      Alternative: relax `requires-python` to `>=3.12` and use platform python.

## Regenerating the lockfiles

- `requirements.txt`: `uv export --frozen --python=3.14 --no-dev --no-editable --no-emit-workspace --output-file requirements.txt`
- `requirements-build.txt`: `printf 'uv\n' | uv pip compile --generate-hashes --python-version 3.14 - -o requirements-build.txt`
- `Gemfile.lock` (needs ruby+bundler+network): `bundle lock --add-platform x86_64-linux`
- `rpms.lock.yaml` (needs rpm-lockfile-prototype + UBI repos): `rpm-lockfile-prototype --local-system rpms.in.yaml` (run inside a UBI10 container)
