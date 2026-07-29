{
  pkgs,
  jail,
  enableGitWorktrees,
}:
let
  inherit (pkgs)
    lib
    ;

  # Normalize the option to { enable, dir, mountGitConfig }, failing fast on
  # bad shapes and unknown keys.
  cfg =
    let
      known = [
        "enable"
        "dir"
        "mountGitConfig"
      ];
      norm =
        if enableGitWorktrees == true then
          { enable = true; }
        else if enableGitWorktrees == false || enableGitWorktrees == null then
          { enable = false; }
        else if builtins.isAttrs enableGitWorktrees then
          enableGitWorktrees
        else
          throw "enableGitWorktrees must be a boolean or an attribute set";
      extra = builtins.attrNames (builtins.removeAttrs norm known);
    in
    if extra != [ ] then
      throw "enableGitWorktrees: unknown key(s) ${lib.concatStringsSep ", " (map (k: "'${k}'") extra)}"
    else
      norm;

  enabled = cfg.enable or false;
  dir = cfg.dir or null;
  mountGitConfig = cfg.mountGitConfig or false;

  # Runtime resolver: when launched from a genuine git worktree, bind its shared
  # `.git` read-write. Verified by checking that `$PWD/.git` is a gitdir file
  # whose target resolves strictly inside the shared `.git` directory, so a
  # crafted pointer at another repo can never be bound.
  resolver =
    let
      gitExe = lib.getExe pkgs.git;
      sedExe = lib.getExe pkgs.gnused;
    in
    jail.combinators.add-runtime ''
      _jwtBindSharedGit() {
        local common_dir gitdir_ref gitdir

        # Shared ".git" directory of the repo we were launched from.
        common_dir="$(${gitExe} -C "$PWD" rev-parse --git-common-dir 2>/dev/null || true)"
        common_dir="$(realpath "$common_dir" 2>/dev/null || true)"

        # A genuine linked worktree has a `.git` *file* pointing at a metadata
        # directory that lives strictly inside the shared ".git". Only then do we
        # bind it read-write: a plain dir, the main repo, or a crafted pointer at
        # another repo fails this check and we bind nothing.
        [ -f "$PWD/.git" ] && [ -n "$common_dir" ] || return 0

        gitdir_ref="$(${sedExe} -n 's/^gitdir: //p' "$PWD/.git" 2>/dev/null | head -n1 || true)"
        gitdir="$(realpath "$gitdir_ref" 2>/dev/null || true)"

        case "$gitdir" in
          "$common_dir"/*) RUNTIME_ARGS+=(--bind "$common_dir" "$common_dir") ;;
        esac
        return 0
      }
      _jwtBindSharedGit
    '';

  perms =
    lib.optional enabled resolver
    ++ lib.optional (enabled && mountGitConfig) (
      jail.combinators.try-readonly (jail.combinators.noescape "~/.gitconfig")
    );
in
{
  readwriteDirs = lib.optional (enabled && dir != null) dir;
  inherit perms;
}
