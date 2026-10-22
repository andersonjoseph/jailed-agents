{
  makePreconfiguredAgent,
  llm-agents,
  pkgs,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-omp";
  defaultPkg = llm-agents.packages.${system}.omp;
  defaultExtraPkgs = [ pkgs.chromium ];
  configPaths = [ "~/.omp" ];
}
