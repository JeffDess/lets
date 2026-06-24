{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world with input";
    args = [
      "firstname"
      "lastname"
    ];
    run = ''
      echo "Hello $firstname $lastname"
    '';
  };
}
