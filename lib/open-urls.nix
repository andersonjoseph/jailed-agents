{
  jail,
  pkgs,
}:
with jail.combinators;
compose [
  (add-pkg-deps [ pkgs.xdg-utils ])
  (set-env "BROWSER" "browserchannel")
  (jail-to-host-channel "browserchannel" ''
    case "$1" in
      https://*|http://*) ''${BROWSER:-xdg-open} "$1" ;;
    esac
  '')
]
