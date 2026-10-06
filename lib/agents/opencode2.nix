{
  makePreconfiguredAgent,
  llm-agents,
  pkgs,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-opencode2";
  defaultPkg = llm-agents.packages.${system}.opencode2;
  defaultExtraPkgs = [ pkgs.xdg-utils ];
  configPaths = [
    "~/.opencode"
    "~/.config/opencode"
    "~/.local/share/opencode"
    "~/.local/state/opencode"
  ];
}
