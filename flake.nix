{
  description = "the AV1 reference tools (aomenc / aomdec) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libaom ships the AV1 reference CLIs aomenc (encode) and aomdec (decode) as
  # "examples" (ENABLE_EXAMPLES, on by default). We build them static and let
  # nix-lib's engine self-fold the two into a single `aom` multicall binary on
  # every target; argv[0] dispatches and the applet names ship as embedded
  # aliases.
  #
  # aom is the same encoder chafa/avif/ffmpeg already cross-build on every
  # target (no nix-lib overlay needed). aomenc/aomdec are C, but libaom.a
  # carries C++ objects (rate control etc.), so the link still pulls the C++
  # runtime — folded in statically by requires.cxx, same as the avif/jxl tools.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;

      # libaom with the two apps built static. nixpkgs hardcodes
      # BUILD_SHARED_LIBS=ON and splits bin/dev/static outputs; we force static,
      # collapse to one output, and build ONLY aomenc/aomdec — ENABLE_EXAMPLES
      # otherwise pulls ~12 example executables (incl. the C++ svc_encoder_rtc),
      # all dead weight.
      mkAomApps = scope:
        let
          lib = scope.lib;
          host = scope.stdenv.hostPlatform;
          # True on every target now: nix-lib turns the engine on for linux and
          # darwin, and multicall.windows = true swaps the whole mingw set onto
          # the engine adapter too. Keyed on the cc name rather than on a
          # per-package stdenv override, so the set-wide swap is seen.
          isEngine = lib.hasInfix "unpin-cc" (scope.stdenv.cc.name or "");
        in
        scope.libaom.overrideAttrs (old: {
          pname = "aom-apps";
          # mingw: aom's find_package(Threads) resolves to a bare `-lpthread`
          # (CMAKE_THREAD_LIBS), which the cmake link of aomenc.exe can't find
          # without winpthreads. (Same as jxl/avif on mingw.)
          buildInputs = (old.buildInputs or [ ])
            ++ lib.optionals host.isMinGW [ scope.windows.pthreads ];
          # libaom carries none of its own; this used to append mingw-only
          # -ffunction-sections/-fdata-sections feeding the fold's --gc-sections
          # post-link. The engine self-fold has no such pass (full LTO prunes
          # instead), so only the base value is left — dropping the attribute
          # outright would unset the variable and move every other target's drv.
          NIX_CFLAGS_COMPILE = old.NIX_CFLAGS_COMPILE or "";
          cmakeFlags =
            (lib.filter (f: !(lib.hasPrefix "-DBUILD_SHARED_LIBS=" f))
              (old.cmakeFlags or [ ]))
            ++ [
              "-DBUILD_SHARED_LIBS=OFF"
              "-DENABLE_EXAMPLES=ON"
              "-DENABLE_TESTS=OFF"
              "-DENABLE_DOCS=OFF"
              "-DENABLE_TOOLS=OFF"
            ]
            # SIMD stays ON: libaom's kernels (sse2/avx2, the per-arch NEON/VSX
            # equivalents) are nasm/intrinsic-asm objects that can't enter the
            # -flto bitcode module, but the engine hook rescues native objects
            # into a sidecar (module_native.a) the self-fold links alongside
            # module.bc, so they resolve. A pure-C `AOM_TARGET_CPU=generic` build
            # would link too — and cost several-fold encode throughput.
            #
            # Drop the optional `--tune=vmaf` path. libvmaf is an EXTERNAL C++
            # library built with GCC/libstdc++ (its <fstream> use references
            # std::basic_filebuf::open(..., std::_Ios_Openmode) — a libstdc++ ABI
            # symbol). The engine links libc++, so libvmaf.a can't resolve against
            # it (the tier-2 external-libstdc++ wall). aom's remaining C++
            # (vendored libwebm/libyuv .cc) is compiled by the engine → libc++, so
            # dropping VMAF makes the whole link libc++-clean. nixpkgs' mingw
            # cross passes CONFIG_TUNE_VMAF=1, so windows used to be the one
            # target shipping the tuner; on the engine it now matches the rest.
            ++ lib.optionals isEngine [ "-DCONFIG_TUNE_VMAF=0" ];
          buildFlags = (old.buildFlags or [ ]) ++ [ "aomenc" "aomdec" ];
          outputs = [ "out" ];
          # bin/dev/static split plumbing is irrelevant — multicall.nix consumes
          # the build-tree objects + aomenc's link.txt and installs its own bin.
          # nixpkgs' meta.outputsToInstall still names the now-removed `bin`
          # output; repoint it at `out` so `nix build` doesn't ask for `bin`.
          postFixup = "";
          postInstall = "";
          # No tests: libaom's suite (ENABLE_TESTS, off above) downloads ~GB of
          # AV1 test vectors over the network — impossible in the Nix sandbox —
          # and runs for a long time. The `--unpin-program=aomenc --help` smoke
          # is the floor.
          doCheck = false;
          meta = (old.meta or { }) // { outputsToInstall = [ "out" ]; };
        });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "aom";
      # gc (function/data-sections + --gc-sections, on by default in nix-lib)
      # needs pkgsAttr = the real lib so the overlay rebuilds it; libaom's
      # dead encoder/decoder paths then get pruned. Measured 10.96 → 8.87 MB
      # (−19.1%) on the static-musl binary.
      pkgsAttr = "libaom";
      smoke = [ "--unpin-program=aomenc" "--help" ];
      smokePattern = "Usage:|aomenc";

      # Build via the unpin-llvm engine + emit a bitcode multicall module. The
      # engine compiles libaom (examples on) and the standalone self-folds
      # aomenc + aomdec into one `aom` binary on every target — Linux, darwin
      # and the mingw cross alike. The apps are pure C, but libaom.a carries
      # VENDORED C++ (rate control etc.), so the self-fold links libc++
      # statically (requires.cxx). There is NO external C++ library, so no
      # forbidden libc++.1.dylib is dragged in — same situation as libvpx.
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [
          { name = "aomenc"; }
          { name = "aomdec"; }
        ];
        requires.cxx = true;
      };

      build = pkgs: mkAomApps pkgs.pkgsStatic;

      windowsBuild = pkgs: mkAomApps (ulib.mingwStaticCross pkgs);
    };
}
