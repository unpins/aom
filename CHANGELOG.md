# Changelog

## [Unreleased]

## [3.12.1-2] - 2026-09-26

### Changed

- Picking a program now uses `--unpin-program=`, the same selector as the rest
  of the catalog: `aom --unpin-program=aomenc …`. The released binary took the
  name positionally (`aom aomenc …`); that form now prints the list of programs
  and exits 1. Installed commands are unaffected — `unpin install aom` still
  gives you plain `aomenc` and `aomdec`.

### Fixed

- The README showed the old positional form throughout, and its `nix build`
  example ran `./result/bin/aomenc`, which is not a file — there is one binary,
  `bin/aom`. Every example now matches what the binary accepts.
- The README claimed you could invoke the bare binary as `aom <program> [args]`.
  You cannot; a bare `aom` prints the list of programs.
- Documented that only `--tune=psnr` and `--tune=ssim` work. `aomenc --help`
  lists seven more metrics — the VMAF family, `butteraugli`, `iq` — and each
  stops with an error, because the libraries they need are not built in.
