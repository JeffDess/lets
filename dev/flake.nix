{
  description = "lets - development inputs";

  inputs = {
    git-hooks.url = "github:cachix/git-hooks.nix";
    dotenv-spec = {
      url = "github:php-xdg/dotenv-spec";
      flake = false;
    };
  };

  outputs = _: { };
}
