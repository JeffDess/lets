let
  flake = builtins.getFlake (toString ../.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  inherit (pkgs) lib;
  prefix = p: lib.mapAttrs' (n: v: lib.nameValuePair "${p}.${n}" v);
  tests =
    prefix "args" (import ./args.nix { inherit pkgs; })
    // prefix "validate" (import ./validate.nix { inherit pkgs; })
    // prefix "mkTask" (import ./mkTask.nix { inherit pkgs; })
    // prefix "mkCompletions" (import ./mkCompletions.nix { inherit pkgs; });
  cases = lib.filterAttrs (n: _: lib.hasInfix ".test" n) tests;
in
lib.mapAttrsToList (name: t: {
  inherit name;
  ok = t.expr == t.expected;
  expected = builtins.toJSON t.expected;
  got = builtins.toJSON t.expr;
}) cases
