let
  flake = builtins.getFlake (toString ../.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  inherit (pkgs) lib;
  tests = import ./mkTask.nix { inherit pkgs; };
  cases = lib.filterAttrs (n: _: lib.hasPrefix "test" n) tests;
in
lib.mapAttrsToList (name: t: {
  inherit name;
  ok = t.expr == t.expected;
  expected = builtins.toJSON t.expected;
  got = builtins.toJSON t.expr;
}) cases
