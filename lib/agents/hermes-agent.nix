{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-hermes-agent";
  defaultPkg = llm-agents.packages.${system}.hermes-agent;
  configPaths = [ "~/.hermes" ];
}
