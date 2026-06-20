{ pkgs, ... }:
{
  demo = {
    description = "Demo Task: Assert hello output in bash, zsh, and nushell";
    app = pkgs.writeShellApplication {
      name = "demo";
      runtimeInputs = [
        pkgs.hello
        pkgs.bash
        pkgs.zsh
        pkgs.nushell
      ];
      text = builtins.readFile ./demo.sh;
    };
  };
}
