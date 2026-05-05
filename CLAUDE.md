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

Binaries built on AlmaLinux 8 (glibc 2.28) are forwards-compatible with AlmaLinux 9 (glibc 2.34). A single rhel8 build can serve both RHEL8 and RHEL9 — verify with `docker run --rm -v ...:... almalinux:9 /path/to/binary --version`.

## GitHub Actions / Releases

Each workflow:
- Triggers on pushes that touch `packages/<name>/`, `build.sh`, or the workflow file itself, and on `<name>-v*` tags
- Builds a matrix of `[rhel8, rhel9]`
- On a `<name>-v*` tag, the `release` job creates a GitHub release and uploads both tarballs + sha256 files

Tag convention for releases: `<package>-v<upstream-version>` (e.g. `leaf-v1.18.2`, `git-v2.54.0`).
