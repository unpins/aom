# aom

Standalone build of the [libaom](https://aomedia.googlesource.com/aom/) AV1 reference command-line programs for the AV1 video codec.

[![CI](https://github.com/unpins/aom/actions/workflows/aom.yml/badge.svg)](https://github.com/unpins/aom/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin aom aomenc --cpu-used=4 -o out.ivf input.y4m
unpin aom aomdec -o decoded.y4m out.ivf
```

To install the programs onto your PATH:

```bash
unpin install aom
```

`unpin install aom` creates the `aomenc` and `aomdec` commands.

## Programs

| command | what it does |
| --- | --- |
| `aomenc` | encode Y4M/YUV → AV1 |
| `aomdec` | decode AV1 → Y4M/YUV |

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

- **Multicall:** one binary at `bin/aom` carries both programs; `aomenc` / `aomdec` are dispatched by `argv[0]`. Invoke the bare binary as `aom <program> [args]` too.
