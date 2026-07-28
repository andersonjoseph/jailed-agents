{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
makePreconfiguredAgent {
  defaultName = "jailed-goose";
  defaultPkg = llm-agents.packages.${system}.goose-cli;
  configPaths = [
    "~/.config/goose"
    "~/.local/share/goose"
    "~/.local/state/goose"
  ];
}
