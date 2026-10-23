{
  makePreconfiguredAgent,
  llm-agents,
  pkgs,
  system,
  jail,
}:
let
  # The jail's /etc is a tmpfs, so fontconfig finds no config and Chromium's
  # renderers die on first text layout (SkFontMgr fatal). Point FONTCONFIG_FILE
  # at a self-contained config; dejavu and the file itself ride in via extraPkgs.
  fontsConf = pkgs.writeText "jailed-omp-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${pkgs.dejavu_fonts}/share/fonts</dir>
      <cachedir prefix="xdg">fontconfig</cachedir>
    </fontconfig>
  '';

  # Chromium records its profile lock as "hostname.pid". When the daemon runs
  # inside a jail it dies with the jail (--die-with-parent) without releasing
  # the lock, and the "jail" hostname makes every later Chromium treat the
  # lock as held by another computer (exit 21, daemon launch failures). Jail
  # locks can never be live at wrapper start; host locks are checked by pid.
  sweepStaleBrowserLocks = jail.combinators.add-runtime ''
    for LOCK in ~/.omp/run/daemons/*/*.profile/SingletonLock ~/.omp/run/daemons/*/daemons/*/*.profile/SingletonLock; do
      [ -L "$LOCK" ] || continue
      TARGET=$(readlink "$LOCK")
      HOST_PART=''${TARGET%.*}
      PID_PART=''${TARGET##*.}
      if [ "$HOST_PART" = "jail" ] || ! kill -0 "$PID_PART" 2>/dev/null; then
        rm -f "''${LOCK%/*}"/Singleton{Lock,Cookie,Socket}
      fi
    done
  '';
in
makePreconfiguredAgent {
  defaultName = "jailed-omp";
  defaultPkg = llm-agents.packages.${system}.omp;
  defaultExtraPkgs = [
    pkgs.chromium
    pkgs.dejavu_fonts
    fontsConf
  ];
  defaultEnv = {
    FONTCONFIG_FILE = "${fontsConf}";
  };
  defaultExtraJailOptions = [ sweepStaleBrowserLocks ];
  configPaths = [ "~/.omp" ];
}
