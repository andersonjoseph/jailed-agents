{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-pi";
  defaultPkg = llm-agents.packages.${system}.pi;
  configPaths = [ "~/.pi" ];
}
