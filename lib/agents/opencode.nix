{
  makePreconfiguredAgent,
  llm-agents,
  pkgs,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-opencode";
  defaultPkg = llm-agents.packages.${system}.opencode;
  defaultExtraPkgs = [ pkgs.xdg-utils ];
  configPaths = [
    "~/.config/opencode"
    "~/.local/share/opencode"
    "~/.local/state/opencode"
  ];
}
