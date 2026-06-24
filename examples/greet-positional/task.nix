{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with positional arguments";
    args = {
      name = {
        type = "positional";
        index = 1;
        required = true;
      };
    };
    run = ''
      # shellcheck disable=SC2154
      echo "Hello $name (the rest stays in \$@: $*)"
    '';
  };
}
