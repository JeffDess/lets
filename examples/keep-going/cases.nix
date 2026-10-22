[
  {
    task = "check";
    status = 1;
    stdout = "fail ran\npass ran";
    stderr = "ERROR: failed: fail";
  }
  {
    task = "strict";
    status = 1;
    stdout = "fail ran";
  }
  {
    task = "own-error";
    status = 1;
    stdout = "";
  }
]
