{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with combined short arguments";
    args = {
      name = {
        short = "n";
        default = "World";
      };
      excited = {
        type = "flag";
        short = "e";
      };
      uppercase = {
        type = "flag";
        short = "u";
      };
    };
    run = ''
      msg="Hello $name"
      if [ "$excited" = true ]; then
        msg="$msg!"
      fi
      if [ "$uppercase" = true ]; then
        msg="''${msg^^}"
      fi
      echo "$msg"
    '';
  };
}
