{
  makePreconfiguredAgent,
  llm-agents,
  pkgs,
  system,
}:
let
  makeOpencode2 = makePreconfiguredAgent {
    defaultName = "jailed-opencode2";
    defaultPkg = llm-agents.packages.${system}.opencode2;
    defaultExtraPkgs = [ pkgs.xdg-utils ];
    configPaths = [
      "~/.opencode"
      "~/.config/opencode"
      "~/.local/share/opencode"
      "~/.local/state/opencode"
      "~/.cache/opencode"
    ];
  };
in
{
  enableClaudeCode ? false,
  extraPkgs ? [ ],
  extraReadwriteDirs ? [ ],
  ...
}@args:
makeOpencode2 (
  removeAttrs args [ "enableClaudeCode" ]
  // {
    extraPkgs =
      extraPkgs ++ pkgs.lib.optional enableClaudeCode llm-agents.packages.${system}.claude-code;
    extraReadwriteDirs =
      extraReadwriteDirs
      ++ pkgs.lib.optionals enableClaudeCode [
        "~/.claude"
        "~/.claude.json"
      ];
  }
)
