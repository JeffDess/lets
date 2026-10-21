{ pkgs }:
let
  inherit (pkgs) lib;
  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix") (
    builtins.readDir ./.
  );
in
lib.mapAttrs' (
  n: _: lib.nameValuePair (lib.removeSuffix ".nix" n) (import ./${n} { inherit pkgs; })
) files
