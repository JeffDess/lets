{ mkTask, tasks, ... }:
{
  pass = mkTask {
    description = "A step that passes";
    run = ''echo "pass ran"'';
  };

  fail = mkTask {
    description = "A step that fails";
    run = ''
      echo "fail ran"
      exit 1
    '';
  };

  check = mkTask {
    description = "Run every step, then report the failures";
    keepGoing = true;
    runtimeInputs = with tasks; [
      fail.app
      pass.app
    ];
    run = ''
      fail
      pass
    '';
  };

  strict = mkTask {
    description = "Stop at the first failing step (the default)";
    runtimeInputs = with tasks; [
      fail.app
      pass.app
    ];
    run = ''
      fail
      pass
    '';
  };

  own-error = mkTask {
    description = "Stop at the task's own failing command, even with keepGoing";
    keepGoing = true;
    runtimeInputs = with tasks; [ pass.app ];
    run = ''
      false
      pass
    '';
  };
}
