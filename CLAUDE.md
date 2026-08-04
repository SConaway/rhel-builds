# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of from-source builds of upstream tools packaged as tarballs for RHEL8 and RHEL9 (using AlmaLinux 8/9 Docker containers). Each package produces a self-contained tarball + sha256 that can be dropped onto a RHEL system without any package manager.

## Building

```bash
./build.sh <package> <rhel-version>
# e.g.
./build.sh git rhel8
./build.sh leaf rhel9
```

Valid RHEL versions: `rhel8`, `rhel9` (or bare `8`, `9`).

Output lands in `output/<package>/<rhel-version>/` (gitignored). The top-level `build.sh` runs the package's own `build.sh` inside the appropriate `almalinux:8` or `almalinux:9` Docker container, mounting the package dir read-only at `/build/package` and the output dir at `/build/output`.

## Testing

```bash
./test.sh <package> [rhel-version]
# e.g.
./test.sh leaf rhel8      # test on AlmaLinux 8 only
./test.sh leaf            # test on both AlmaLinux 8 and 9
```

Must build first (`./build.sh`). When no rhel-version is given, rhel9 falls back to the rhel8 tarball automatically (glibc forwards-compat). Each package's `packages/<name>/test.sh` receives the unpacked artifact root as `$1` and should exit non-zero on failure.

## Adding a new package

1. Create `packages/<name>/build.sh` — this runs inside the container as root.
2. Add `.github/workflows/<name>.yml` — copy an existing workflow and substitute the package name and tag prefix.

### Package build.sh conventions

- Detect distro inside the container: `DISTRO_ID=$(. /etc/os-release && echo "${ID}")` → e.g. `almalinux8`
- Artifact naming: `<name>-<version>-<platform>-<arch>` (e.g. `leaf-1.18.2-almalinux8-x86_64`)
- Stage into `/build/staging/<artifact-name>/`, tar from `/build/staging/`, write to `/build/output/`
- Always produce a `.sha256` alongside the tarball
- For Rust packages: install rustup with `RUSTUP_HOME=/build/rustup CARGO_HOME=/build/cargo` and `source /build/cargo/env` so the toolchain is isolated from any host state

### Portability note

Binaries built on AlmaLinux 8 (glibc 2.28) are forwards-compatible with AlmaLinux 9 (glibc 2.34). **Always build on AlmaLinux 8 first and verify it runs on AlmaLinux 9 with `./test.sh <package> rhel9`.** Only add a separate rhel9 build if the rhel8 binary is confirmed to not work on RHEL9 — separate builds and releases are a last resort, not the default.

## GitHub Actions / Releases

Each workflow:
- Triggers on branch pushes that touch `packages/<name>/`, `build.sh`, or the workflow file itself, and on `<name>-v*` tags. **Both `branches: ['**']` and `tags` must be present under `push`** — omitting `branches` causes GitHub Actions to silently ignore branch pushes when a `tags` filter is present.
- Builds rhel8 only (AlmaLinux 8 binaries run on both RHEL8 and RHEL9 due to glibc forwards-compatibility)
- On a `<name>-v*` tag, the `release` job creates a GitHub release and uploads the tarball + sha256
- Only add an rhel9 build job if the rhel8 binary is confirmed not to work on RHEL9 (see portability note above)

Tag convention for releases: `<package>-v<upstream-version>` (e.g. `leaf-v1.18.2`, `git-v2.54.0`).

**Always push the branch and tags together in a single command** — if you push the branch first and tags separately, GitHub evaluates the tag push as having no file diff and the `paths` filter silently skips the workflow. Push everything at once:

```bash
git push origin main git-v2.55.0 leaf-v1.25.0  # etc.
```

## Automated update checking

`.github/workflows/check-updates.yml` runs every 6 hours (and on `workflow_dispatch`) via `scripts/check-updates.sh`. For each `packages/<name>/build.sh` with a `VERSION="..."` line, it looks up the latest upstream version, and if it differs, patches `VERSION=`, pushes a `bump/<name>` branch, and opens (or updates, if one is already open) a PR. This is deterministic shell/CLI, not LLM-driven — no agent involved in the loop.

`.github/workflows/tag-on-merge.yml` fires on `pull_request: closed` for any `bump/<name>` branch that was merged. It re-reads `VERSION=` from `main` post-merge and pushes the `<name>-v<version>` tag via `scripts/tag-on-merge.sh`, which then triggers the package's existing release workflow unchanged. Tagging is fully automatic; merging the bump PR is not — a human always reviews and merges it first.

Version lookup (`scripts/get-latest-version.sh <pkg>`) defaults to checking the GitHub releases/tags of the repo in `SOURCE_URL`. If a package's upstream isn't a GitHub-tagged release — a non-GitHub host (e.g. `git`, which builds from a kernel.org tarball), a dynamically-computed `VERSION` (e.g. `meld`, whose version comes from `rpm -q`), or a repo whose tags need filtering/sorting beyond a plain "latest" — add `packages/<name>/check-version.sh` (executable, no args, prints the latest upstream version to stdout with no leading `v`). If present, it always overrides the generic checker. Packages with no static `VERSION="..."` line (like `meld`) are silently skipped by the checker rather than erroring.

One-time manual setup:
- Repo Settings → Actions → General → Workflow permissions must have "Allow GitHub Actions to create and approve pull requests" enabled, or `gh pr create`/`gh pr edit` in `check-updates.sh` will fail. This can't be set via the API.
- `tag-on-merge.yml` and `check-updates.yml` both need a `RELEASE_TAG_PAT` repo secret (Settings → Secrets and variables → Actions): a personal access token (classic or fine-grained, `contents: write` + `pull_requests: write` on this repo) used to push tags/branches and open PRs as a real user instead of `GITHUB_TOKEN`. **This is required, not optional** — pushes/tags/PRs made with the default `GITHUB_TOKEN` are attributed to `github-actions[bot]`, and GitHub's loop-prevention rule silently blocks anything triggered by that token from firing other workflows' `push`/`pull_request`/`on.push.tags` triggers. For `tag-on-merge.yml` that means the per-package release workflow never fires; for `check-updates.yml` it means the per-package build workflow never runs on the bump PR (looks like it's stuck waiting on manual approval). A PAT belonging to a real user avoids both.
