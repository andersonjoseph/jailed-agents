{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-omp";
  defaultPkg = llm-agents.packages.${system}.omp;
  configPaths = [ "~/.omp" ];
}
