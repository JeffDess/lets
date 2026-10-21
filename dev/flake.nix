{
  description = "lets - development inputs";

  inputs = {
    git-hooks.url = "github:cachix/git-hooks.nix";
    nix-unit.url = "github:nix-community/nix-unit";
    dotenv-spec = {
      url = "github:php-xdg/dotenv-spec";
      flake = false;
    };
  };

  outputs = _: { };
}
