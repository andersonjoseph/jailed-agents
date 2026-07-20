{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-crush";
  defaultPkg = llm-agents.packages.${system}.crush;
  configPaths = [
    "~/.config/crush"
    "~/.local/share/crush"
  ];
}
