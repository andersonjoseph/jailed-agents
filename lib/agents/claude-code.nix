{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-claude-code";
  defaultPkg = llm-agents.packages.${system}.claude-code;
  configPaths = [
    "~/.claude"
    "~/.claude.json"
  ];
}
