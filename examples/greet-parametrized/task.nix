{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with input";
    args = {
      name = {
        description = "Hello world with input and default value";
        short = "n";
        default = [
          "$USER"
          "World"
        ];
        required = true;
        type = "option";
      };
    };
    run = ''
      echo "Hello $name"
    '';
  };
}
