{
  description = "the AV1 reference tools (aomenc / aomdec) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # libaom ships the AV1 reference CLIs aomenc (encode) and aomdec (decode) as
  # "examples" (ENABLE_EXAMPLES, on by default). We build them static and
  # post-link the two into a single `aom` multicall binary (multicall.nix);
  # argv[0] dispatches and lib.withAliases embeds the names as UNPIN_META.
  #
  # aom is the same encoder chafa/avif/ffmpeg already cross-build on every
  # target (no nix-lib overlay needed). aomenc/aomdec are C, but libaom.a
  # carries C++ objects (rate control etc.), so the link still pulls the C++
  # runtime — folded in statically per platform (darwin libc++, mingw
  # -static-libstdc++), same as the avif/jxl tools.
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
        in
        scope.libaom.overrideAttrs (old: {
          pname = "aom-apps";
          # mingw: aom's find_package(Threads) resolves to a bare `-lpthread`
          # (CMAKE_THREAD_LIBS), which the cmake link of aomenc.exe can't find
          # without winpthreads. (Same as jxl/avif on mingw.)
          buildInputs = (old.buildInputs or [ ])
            ++ lib.optionals host.isMinGW [ scope.windows.pthreads ];
          # mingw: function/data-sections so the lld-driven multicall link
          # (-fuse-ld=lld -Wl,--gc-sections in windowsBuild) can dead-strip
          # libaom's unreachable encoder/decoder code from the .exe. On Linux
          # the gc overlay already injects these chain-wide; this only fires
          # on the mingw cross (no overlay there), so native/darwin unchanged.
          NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "")
            + lib.optionalString host.isMinGW " -ffunction-sections -fdata-sections";
          cmakeFlags =
            (lib.filter (f: !(lib.hasPrefix "-DBUILD_SHARED_LIBS=" f))
              (old.cmakeFlags or [ ]))
            ++ [
              "-DBUILD_SHARED_LIBS=OFF"
              "-DENABLE_EXAMPLES=ON"
              "-DENABLE_TESTS=OFF"
              "-DENABLE_DOCS=OFF"
              "-DENABLE_TOOLS=OFF"
            ];
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
          # and runs for a long time. The `aomenc --help` smoke is the floor.
          doCheck = false;
          meta = (old.meta or { }) // { outputsToInstall = [ "out" ]; };
        });

      mk = pkgs: scope: extra:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          ({ pkgs = scope; libaomApps = mkAomApps scope; } // extra);
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "aom";
      # gc (function/data-sections + --gc-sections, on by default in nix-lib)
      # needs pkgsAttr = the real lib so the overlay rebuilds it; libaom's
      # dead encoder/decoder paths then get pruned. Measured 10.96 → 8.87 MB
      # (−19.1%) on the static-musl binary.
      pkgsAttr = "libaom";
      smoke = [ "aomenc" "--help" ];
      smokePattern = "Usage:|aomenc";

      # darwin: libaom.a's C++ objects pull `-lc++` → /usr/lib/libc++.1.dylib,
      # which the unpins darwin allowlist rejects; fold libc++ in statically
      # (same branch as avif/jxl/vpx).
      build = pkgs:
        let sp = pkgs.pkgsStatic; in
        mk pkgs sp (pkgs.lib.optionalAttrs sp.stdenv.hostPlatform.isDarwin {
          extraLinkFlags = "-nostdlib++ ${sp.libcxx}/lib/libc++.a ${sp.libcxx}/lib/libc++abi.a";
        });

      # mingw cross: -static* folds libgcc + libstdc++ (libaom.a's C++) into the
      # .exe so no companion DLLs ride alongside.
      windowsBuild = pkgs:
        let cross = ulib.mingwStaticCross pkgs; in
        mk pkgs cross {
          # -static* folds libgcc + libstdc++ (libaom.a's C++) into the .exe.
          # The linker (lld) + --gc-sections + --icf=safe come uniformly from
          # lib.gcSectionsFlag (appended in multicall.nix); on PE that also
          # sidesteps GNU ld's --gc-sections regression.
          extraLinkFlags = "-static -static-libgcc -static-libstdc++";
        };
    };
}
