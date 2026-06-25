let __lets_prev = ($env.config.completions.external.completer? | default null)
$env.config.completions.external.completer = {|spans|
  if ($spans | length) > 0 and ($spans | first) == "lets" {
    ^lets __complete ...$spans
    | lines
    | where ($it | str length) > 0
    | each {|line|
        let p = ($line | split row "\t")
        {value: ($p | get 0), description: ($p | get 1? | default "")}
      }
  } else if $__lets_prev != null {
    do $__lets_prev $spans
  } else {
    null
  }
}
