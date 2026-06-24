{ mkTask, ... }:
{
  greet = mkTask {
    description = "Hello world in color";
    run = ''
      bold_blue "Hello, World!"
    '';
  };
}
