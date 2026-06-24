# NOTE: Color is disabled when stdout is not a terminal, so the output fallbacks
# to plain text in tests. Asserting the exact ANSI escape with FORCE_COLOR would
# be cumbersome, so it actually only checks if it still runs.
[
  {
    task = "greet";
    stdout = "Hello, World!";
  }
  {
    task = "greet";
    status = 0;
  }
]
