{ pkgs, mkTask, ... }:
{
  demo = mkTask {
    description = "Demo Task: Assert hello output in bash, zsh, and nushell";
    runtimeInputs = with pkgs; [
      bash
      zsh
      nushell
      hello
    ];
    args = {
      locale = {
        description = "Locale used for the hello output";
        short = "l";
        default = "en_US";
      };
      name = {
        description = "Name to greet";
        type = "positional";
        index = 1;
        default = "World";
      };
    };
    run = builtins.readFile ./demo.sh;
  };
}
