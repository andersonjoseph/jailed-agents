{
  pkgs,
}:
{
  agents,
  dir ? ".direnv/t3",
}:
let
  inherit (pkgs)
    lib
    ;

  entryFor =
    item:
    let
      fromDerivation = d: {
        agent = d;
        args = [ ];
        name = baseNameOf (lib.getExe d);
      };
    in
    if lib.isDerivation item then
      fromDerivation item
    else if item ? agent && lib.isDerivation item.agent then
      fromDerivation item.agent
      // {
        args = item.args or [ ];
        name = item.name or (baseNameOf (lib.getExe item.agent));
      }
    else
      throw "makeT3WrappersHook: each agent must be a derivation or an attrset with an 'agent' derivation";

  entries = map entryFor agents;

  names = map (entry: entry.name) entries;

  duplicates = lib.filter (n: builtins.length (lib.filter (m: m == n) names) > 1) (lib.unique names);

  keepPattern =
    if names == [ ] then "''" else lib.concatStringsSep "|" (map lib.escapeShellArg names);

  wrapperBlock =
    entry:
    let
      storePath = toString entry.agent;
      execLines = map (arg: "printf ' %q' ${lib.escapeShellArg arg}") entry.args ++ [
        "printf '%s\\n' ' \"$@\"'"
      ];
    in
    ''
      name=${lib.escapeShellArg entry.name}
      {
        printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
        printf 'repo=%q\n' "$root"
        printf '%s\n' 'case $PWD in' '  "$repo" | "$repo"/* | "$HOME/.t3/worktrees/''${repo##*/}"/*) ;;' '  *) cd "$repo" ;;' 'esac'
        printf 'exec %q' ${lib.escapeShellArg (lib.getExe entry.agent)}
      ${lib.concatStringsSep "\n" execLines}
      } >"$out/$name.tmp"
      chmod +x "$out/$name.tmp"
      mv "$out/$name.tmp" "$out/$name"
      nix-store --realise ${lib.escapeShellArg storePath} --add-root "$out/.gcroots/$name" >/dev/null
    '';
in
if duplicates != [ ] then
  throw "makeT3WrappersHook: duplicate agent name(s): ${lib.concatStringsSep ", " duplicates}"
else
  ''
    _jailedAgentsT3Hook() {
      local root="$PWD" out name gc
      while [ ! -e "$root/flake.nix" ] && [ "$root" != "/" ]; do
        root="$(dirname "$root")"
      done
      if [ ! -e "$root/flake.nix" ]; then
        return 0
      fi
      out=$root/${lib.escapeShellArg dir}
      mkdir -p "$out/.gcroots"
      for gc in "$out"/.gcroots/*; do
        [ -L "$gc" ] || continue
        name="''${gc##*/}"
        case "$name" in
          ${keepPattern}) ;;
          *) rm -f -- "$out/$name" "$gc" ;;
        esac
      done
    ${lib.concatStringsSep "\n" (map wrapperBlock entries)}
    }
    _jailedAgentsT3Hook
    unset -f _jailedAgentsT3Hook
  ''
