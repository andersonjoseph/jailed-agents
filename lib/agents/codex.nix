{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-codex";
  defaultPkg = llm-agents.packages.${system}.codex;
  configPaths = [ "~/.codex" ];
}
