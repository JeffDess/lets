{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with uppercase option";
    args = {
      firstname = {
        default = "World";
      };
      lastname = { }; # same as `lastname = { type = "option"; };`
      uppercase = {
        type = "flag";
      };
    };
    run = ''
      # shellcheck disable=2154,2289,1089
      msg="Hello $firstname''${lastname:+ $lastname}!"
      if [ $uppercase = true ]; then
        msg="''${msg^^}"
      fi
      echo "$msg"
    '';
  };
}
