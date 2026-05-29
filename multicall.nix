# libaom builds aomenc (encode) and aomdec (decode) as "example" executables.
# To honour the unpins one-pkg-one-bin rule we post-link them into a single
# multicall binary at $out/bin/aom; `lib.withAliases` then embeds the tool
# names as an UNPIN_META block so unpin's installer recreates the argv[0] shims.
#
# Link mechanics (same family as avif/jxl — CMake "Unix Makefiles" generator):
#
#   * Reuse aomenc's `CMakeFiles/aomenc.dir/link.txt` — it carries the exact
#     compiler/flags/libs plus the common+encoder app-util OBJECT-lib members
#     ($<TARGET_OBJECTS:…> expand to explicit .o paths) and libaom + syslibs.
#     Splice in aomdec's main object, the dispatcher, and the *decoder*
#     app-util objects (aomdec needs them; they are NOT in aomenc's link), then
#     retarget the output.
#
#   * aomenc/aomdec are pure C (apps/aomenc.c, apps/aomdec.c), so the link is C
#     (no libc++/mcfgthread to fold). Each tool's only strong clash is `main`,
#     renamed per-tool; the iterative pass is insurance against any other.
{ lib }:
{ pkgs, libaomApps, name ? "aom", primary ? "aomenc", extraLinkFlags ? "" }:
let
  TOOLS = [
    { tool = "aomenc"; src = "apps/aomenc.c"; }
    { tool = "aomdec"; src = "apps/aomdec.c"; }
  ];
  toolsBash = lib.concatMapStringsSep " " (t: "${t.tool}:${t.src}") TOOLS;

  multicall = libaomApps.overrideAttrs (old: {
    pname = "aom-multi";
    outputs = [ "out" ];
    separateDebugInfo = false;
    postInstall = "";

    postBuild = (old.postBuild or "") + ''
      mkdir -p multicall
      printf '%s\n' ${lib.escapeShellArg toolsBash} | tr ' ' '\n' > multicall/tools.map

      oext=o
      [ -n "$(find . -path '*${primary}.dir/apps/${primary}.c.obj' -print -quit)" ] && oext=obj

      : > multicall/apps.list
      declare -A OBJ
      while IFS=: read -r tool src; do
        [ -n "$tool" ] || continue
        obj="$(find . -path "*$tool.dir/$src.$oext" | head -1)"
        [ -n "$obj" ] || { echo "multicall: object for $tool ($src.$oext) not found" >&2; exit 1; }
        OBJ[$tool]="$obj"
        echo "$tool" >> multicall/apps.list
      done < multicall/tools.map
      [ -s multicall/apps.list ] || { echo "multicall: no tool objects found" >&2; exit 1; }

      linktxt="$(find . -path "*${primary}.dir/link.txt" | head -1)"
      [ -n "$linktxt" ] || { echo "multicall: ${primary} link.txt not found (non-Makefile generator?)" >&2; exit 1; }

      # aomenc's link.txt lacks the decoder app-util OBJECT-lib members that
      # aomdec needs (its $<TARGET_OBJECTS:aom_decoder_app_util> set). Splice
      # those in too. (common app-util is shared and already in aomenc's link.)
      dec_objs="$(find . -path "*aom_decoder_app_util.dir/*.$oext" | sort | tr '\n' ' ')"

      # Symbol prefix (Mach-O leads C symbols with '_'), read from the primary.
      if $NM --defined-only "''${OBJ[${primary}]}" | awk '$3=="_main"{f=1} END{exit !f}'; then
        up=_
      else
        up=""
      fi

      # Distinct entry points: rename each tool's main → <tool>_main.
      while IFS= read -r tool; do
        $OBJCOPY --redefine-sym "''${up}main=''${up}''${tool}_main" "''${OBJ[$tool]}"
      done < multicall/apps.list

      # Dispatcher.
      {
        echo '#include <string.h>'
        echo '#include <stdio.h>'
        while IFS= read -r tool; do echo "int ''${tool}_main(int, char **);"; done < multicall/apps.list
        echo 'struct applet { const char *name; int (*fn)(int, char **); };'
        echo 'static const struct applet applets[] = {'
        while IFS= read -r tool; do echo "    {\"$tool\", ''${tool}_main},"; done < multicall/apps.list
        cat <<'CBODY'
    {0, 0}
};
static void copy_basename(char *dst, size_t cap, const char *src) {
    const char *p = src, *s;
    s = strrchr(p, '/'); if (s) p = s + 1;
#ifdef _WIN32
    s = strrchr(p, '\\'); if (s) p = s + 1;
#endif
    size_t n = strlen(p); if (n >= cap) n = cap - 1;
    memcpy(dst, p, n); dst[n] = 0;
    if (n > 4 && strcmp(dst + n - 4, ".exe") == 0) dst[n - 4] = 0;
}
CBODY
        cat <<CBODY
static int usage(const char *a0) {
    fprintf(stderr, "${name}: multicall binary; usage: %s <applet> [args]\n", a0);
    fprintf(stderr, "applets:");
    for (const struct applet *a = applets; a->name; a++)
        fprintf(stderr, " %s", a->name);
    fprintf(stderr, "\n");
    return 1;
}
int main(int argc, char **argv) {
    char base[64];
    const char *a0 = (argc > 0 && argv[0]) ? argv[0] : "${name}";
    copy_basename(base, sizeof base, a0);
    /* Invoked under an applet name (an argv[0] shim) -> run it directly. */
    for (const struct applet *a = applets; a->name; a++)
        if (strcmp(base, a->name) == 0) return a->fn(argc, argv);
    /* Invoked as the multicall binary under ANY other name -- its own
       "${name}", a full path, or a copy/rename like CI's smoke.exe -> take
       argv[1] as the applet. */
    if (argc < 2) return usage(a0);
    copy_basename(base, sizeof base, argv[1]);
    for (const struct applet *a = applets; a->name; a++)
        if (strcmp(base, a->name) == 0) return a->fn(argc - 1, argv + 1);
    fprintf(stderr, "${name}: unknown applet '%s'\n", base);
    return usage(a0);
}
CBODY
      } > multicall/dispatcher.c
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Splice the non-primary tool mains + decoder app-util objects + the
      # dispatcher in front of the output, retargeting to multicall/${name}.
      # link.txt paths are relative to its build dir (`.` for aom's top-level
      # generator); make the spliced objects absolute so they survive the cd.
      top="$PWD"
      linkdir="''${linktxt%/CMakeFiles/*}"
      out_bin="$top/multicall/${name}"
      disp="$top/multicall/dispatcher.o"
      extra_objs=""
      while IFS= read -r tool; do
        [ "$tool" = "${primary}" ] && continue
        extra_objs="$extra_objs $top/''${OBJ[$tool]#./}"
      done < multicall/apps.list
      for o in $dec_objs; do extra_objs="$extra_objs $top/''${o#./}"; done
      linkbase="$(sed -E "s| -o (\"?)${primary}(\.exe)?(\"?)|$extra_objs $disp -o $out_bin|" "$linktxt") ${extraLinkFlags}"

      # Iterative link: each failed attempt names remaining strong duplicates.
      # aomenc/aomdec each define app-provided hooks the shared tools_common.c
      # calls by name (usage_exit, exec_name, …). Renaming in *both* would leave
      # tools_common's reference undefined, so instead keep ONE definition
      # global (the first definer in apps.list — the primary) and --localize the
      # symbol in the other tool objects: the shared ref binds to the primary's
      # copy; each tool's own direct refs bind to its now-local copy. (`main` is
      # already renamed per-tool above, so it never reaches this loop.)
      converged=0
      for _ in $(seq 1 20); do
        if ( cd "$linkdir" && eval "$linkbase" ) 2>multicall/link.err; then converged=1; break; fi
        cat multicall/link.err >&2
        sed -nE "s/.*multiple definition of [\`']([^']+)'.*/\1/p; s/.*duplicate symbol '([^']+)'.*/\1/p" \
          multicall/link.err | sort -u > multicall/clash.syms
        [ -s multicall/clash.syms ] || { echo "multicall: link failed without a duplicate-symbol diagnostic" >&2; exit 1; }
        while IFS= read -r sym; do
          kept=0; hit=0
          while IFS= read -r tool; do
            obj="''${OBJ[$tool]}"
            raw=$($NM --defined-only "$obj" | awk -v s="$sym" '$3==s {print $3; exit}')
            [ -n "$raw" ] || continue
            hit=1
            if [ "$kept" = 0 ]; then kept=1; continue; fi
            $OBJCOPY --localize-symbol="$raw" "$obj"
          done < multicall/apps.list
          [ "$hit" = 1 ] || { echo "multicall: clashing symbol '$sym' not defined by any tool object" >&2; exit 1; }
        done < multicall/clash.syms
      done
      [ "$converged" = 1 ] || { echo "multicall: link did not converge in 20 passes" >&2; exit 1; }

      [ -f multicall/${name} ] || mv multicall/${name}.exe multicall/${name}
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m755 multicall/${name} "$out/bin/${name}"
      while IFS= read -r a; do
        [ -n "$a" ] && ln -s ${name} "$out/bin/$a"
      done < multicall/apps.list
      runHook postInstall
    '';
  });
  aliased = lib.withAliases pkgs
    {
      primary = name;
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if pkgs.stdenv.hostPlatform.isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/${name}" ] && mv "$out/bin/${name}" "$out/bin/${name}.exe"
  '';
})
else aliased
