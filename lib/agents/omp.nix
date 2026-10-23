{
  makePreconfiguredAgent,
  llm-agents,
  pkgs,
  system,
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
  configPaths = [ "~/.omp" ];
}
