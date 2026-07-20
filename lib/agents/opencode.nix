{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-opencode";
  defaultPkg = llm-agents.packages.${system}.opencode;
  configPaths = [
    "~/.config/opencode"
    "~/.local/share/opencode"
    "~/.local/state/opencode"
  ];
}
