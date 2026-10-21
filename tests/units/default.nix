{ pkgs }:
let
  inherit (pkgs) lib;
  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix") (
    builtins.readDir ./.
  );
  suites = lib.mapAttrs' (
    n: _: lib.nameValuePair (lib.removeSuffix ".nix" n) (import ./${n} { inherit pkgs; })
  ) files;
in
suites
// {
  naming.testEveryCaseIsNamedTest = {
    expr = lib.concatLists (
      lib.mapAttrsToList (
        suite: cases:
        map (case: "${suite}.${case}") (
          builtins.filter (case: !lib.hasPrefix "test" case) (builtins.attrNames cases)
        )
      ) suites
    );
    expected = [ ];
  };
}
