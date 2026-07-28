{
  makePreconfiguredAgent,
  llm-agents,
  system,
}:
{
  makeJailedClaudeCode = import ./claude-code.nix {
    inherit makePreconfiguredAgent llm-agents system;
  };
  makeJailedCodex = import ./codex.nix {
    inherit makePreconfiguredAgent llm-agents system;
  };
  makeJailedCrush = import ./crush.nix {
    inherit makePreconfiguredAgent llm-agents system;
  };
  makeJailedGoose = import ./goose.nix {
    inherit makePreconfiguredAgent llm-agents system;
  };
  makeJailedHermesAgent = import ./hermes-agent.nix {
    inherit makePreconfiguredAgent llm-agents system;
  };
  makeJailedOpencode = import ./opencode.nix {
    inherit makePreconfiguredAgent llm-agents system;
  };
  makeJailedPi = import ./pi.nix {
    inherit makePreconfiguredAgent llm-agents system;
  };
}
