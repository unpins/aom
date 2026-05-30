# aom

Standalone build of the [libaom](https://aomedia.googlesource.com/aom/) AV1 reference command-line tools — `aomenc` (encode) and `aomdec` (decode) for the AV1 video codec.

[![CI](https://github.com/unpins/aom/actions/workflows/aom.yml/badge.svg)](https://github.com/unpins/aom/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin aom
```

This drops both `aomenc` and `aomdec` on your PATH (they are argv[0] shims into one multicall binary).

## Build locally

```bash
nix build github:unpins/aom
./result/bin/aomenc --cpu-used=4 -o out.ivf input.y4m
./result/bin/aomdec -o decoded.y4m out.ivf
```

Or run directly:

```bash
nix run github:unpins/aom -- aomenc --help
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/aom/releases) page has standalone binaries for manual download.

## Build notes

- **Multicall:** one binary at `bin/aom` carries both tools; `aomenc` / `aomdec` are dispatched by `argv[0]`. Invoke the bare binary as `aom <tool> [args]` too.
- **Codec:** the AV1 reference encoder/decoder. Reads/writes y4m, raw YUV, IVF and OBU.
- **Windows:** `mingw` cross, single `.exe`, no companion DLLs.
- **macOS:** static `.a` codec + C++ runtime linked in; only system frameworks/libSystem stay dynamic.
- **No embedded resources:** pure codec CLI — nothing baked in beyond the code, and libaom ships no man pages (no `unpin man` entry).
- **Tests:** libaom's suite isn't run — it downloads ~GB of AV1 test vectors over the network (impossible in the build sandbox) and runs for a long time. The `aomenc --help` smoke is the floor.

`aomenc` is thorough but slow — for everyday AV1 transcoding [ffmpeg](https://github.com/unpins/ffmpeg) (which links the same libaom) is usually the better tool; `aom` is here for reference-encoder access and AV1 conformance work.
