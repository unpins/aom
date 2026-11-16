# aom

The [libaom](https://aomedia.googlesource.com/aom/) AV1 reference command-line programs for the AV1 video codec, as a single self-contained binary built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/aom/actions/workflows/aom.yml/badge.svg)](https://github.com/unpins/aom/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install aom`.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin aom --unpin-program=aomenc --cpu-used=4 -o out.ivf input.y4m
unpin aom --unpin-program=aomdec -o decoded.y4m out.ivf
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
./result/bin/aom --unpin-program=aomenc --cpu-used=4 -o out.ivf input.y4m
./result/bin/aom --unpin-program=aomdec -o decoded.y4m out.ivf
```

Or run directly:

```bash
nix run github:unpins/aom -- --unpin-program=aomenc --help
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/aom/releases) page has standalone binaries for manual download.

## Build notes

- **Both programs, one binary.** `unpin install aom` gives you `aomenc` and `aomdec` as ordinary commands; without installing, pick one with `--unpin-program=aomenc`.
- **No man pages** — libaom ships none for `aomenc`/`aomdec`; run with `--help`.
- **Tuning metrics:** every `--tune=` value works except `butteraugli`, which needs libjxl's butteraugli library (nixpkgs leaves it out too); aomenc stops with *"Tried to set control 24"* if you ask for it. The VMAF family (`vmaf`, `vmaf_neg`, `vmaf_with_preprocessing`, `vmaf_without_preprocessing`) needs a VMAF model file: pass `--vmaf-model-path=vmaf_v0.6.1.json` (the models ship with [libvmaf](https://github.com/Netflix/vmaf/tree/master/model)), since the default path, `/usr/local/share/model`, does not exist on most systems. `iq` needs `--allintra`. `vmaf_saliency_map` is accepted but encodes like the default: the saliency map is an experimental option upstream builds without.
- **Windows:** mingw.
- **Tests:** libaom's test suite is not run: it downloads several GB of AV1 test vectors over the network, which the build sandbox does not allow.
