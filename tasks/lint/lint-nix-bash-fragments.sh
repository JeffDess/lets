#!/usr/bin/env bash

# Strict attr names that usually contain shell code in nixpkgs-style files.
# editorconfig-checker-disable-next-line
ATTR_RE='(pre[a-zA-Z0-9_]*|post[a-zA-Z0-9_]*|[a-zA-Z0-9_]*Phase|shellHook|run|script|buildCommand|checkPhase|installCheckPhase|text)'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mapfile -t nix_files < <(
  find . -type f -name '*.nix' \
    -not -path '*/.git/*' \
    -not -path '*/.direnv/*' \
    -not -path '*/result/*' |
    sort
)
if ((${#nix_files[@]} == 0)); then
  echo "No .nix files found"
  exit 0
fi

extract_count=0

for file in "${nix_files[@]}"; do
  # editorconfig-checker-disable-next-line
  awk -v file="$file" -v outdir="$tmpdir" -v attr_re="$ATTR_RE" -v start_n="$extract_count" '
      function leading_ws_len(s,    m) {
        match(s, /^[ \t]*/)
        return RLENGTH
      }

      function render(s,    out, i, c, c2, c3, top, r, step) {
        out = ""
        i = 1
        while (i <= length(s)) {
          c = substr(s, i, 1)
          c2 = substr(s, i, 2)
          c3 = substr(s, i, 3)
          top = stack[sp]
          r = ""
          step = 1
          if (top == "code") {
            if (c == "#") {
              break
            } else if (c == "{") {
              stack[++sp] = "code"
            } else if (c == "}") {
              sp--
            } else if (c == "\"") {
              stack[++sp] = "str"
            } else if (c2 == "\047\047") {
              stack[++sp] = "ind"
              step = 2
            }
          } else if (top == "str" && c == "\\") {
            step = 2
          } else if (top == "str" && c == "\"") {
            sp--
          } else if (top != "str" && c3 == "\047\047\047") {
            r = "\047\047"
            step = 3
          } else if (top != "str" && c3 == "\047\047$") {
            r = "$"
            step = 3
          } else if (top != "str" && c3 == "\047\047\\") {
            r = substr(s, i + 3, 1)
            step = 4
          } else if (top == "ind" && c2 == "\047\047") {
            sp--
            step = 2
          } else if (c2 == "$$") {
            r = c2
            step = 2
          } else if (c2 == "${") {
            r = "__NIX_INTERP__"
            stack[++sp] = "code"
            step = 2
          } else {
            r = c
          }
          if (top == "bash") out = out r
          i += step
        }
        return out
      }

      function start_block(attr, line_no) {
        in_block = 1
        sp = 0
        block_attr = attr
        block_start = line_no
        block_path = outdir "/" (++n) ".sh"
        block_line_count = 0
        block_base_indent = -1
        print "#!/usr/bin/env bash" > block_path
        # editorconfig-checker-disable-next-line
        print "# source: " file ":" block_start " attr=" block_attr >> block_path
        if (attr == "run") print "# shellcheck disable=SC2154" >> block_path
      }

      function end_block() {
        if (pending != "") {
          block_lines[++block_line_count] = pending
          pending = ""
        }
        for (i = 1; i <= block_line_count; i++) {
          line = block_lines[i]
          if (line ~ /^[ \t]*$/) {
            print "" >> block_path
          } else {
            if (block_base_indent > 0) {
              indent = leading_ws_len(line)
              if (indent >= block_base_indent) {
                print substr(line, block_base_indent + 1) >> block_path
              } else {
                print line >> block_path
              }
            } else {
              print line >> block_path
            }
          }
        }
        close(block_path)
        delete block_lines
        in_block = 0
        block_attr = ""
        block_start = 0
        block_path = ""
        block_line_count = 0
        block_base_indent = -1
      }

      BEGIN {
        in_block = 0
        n = start_n
        stack[0] = "bash"
      }

      {
        line = $0

        if (!in_block) {
          # Match: attrName = two-single-quotes (allow whitespace)
          # editorconfig-checker-disable-next-line
          if (line ~ "^[[:space:]]*" attr_re "[[:space:]]*=[[:space:]]*\\047\\047[[:space:]]*$") {
            attr = line
            sub(/^[[:space:]]*/, "", attr)
            sub(/[[:space:]]*=.*/, "", attr)
            start_block(attr, NR)
          }
          next
        }

        # End of indented string marker + semicolon.
        if (!sp && line ~ /^[[:space:]]*\047\047[[:space:]]*;[[:space:]]*$/) {
          end_block()
          next
        }

        # Neutralize nix interpolation so shellcheck/shfmt can parse.
        pending = pending render(line)
        if (sp) next
        line = pending
        pending = ""
        block_lines[++block_line_count] = line
        if (line !~ /^[ \t]*$/ && block_base_indent < 0) {
          block_base_indent = leading_ws_len(line)
        }
      }

      END {
        if (in_block) {
          # Unclosed block; still flush for visibility.
          end_block()
        }
        print n
      }
    ' "$file" >"$tmpdir/.count.$$"

  c="$(<"$tmpdir/.count.$$")"
  rm -f "$tmpdir/.count.$$"
  extract_count="$c"
done

if ((extract_count == 0)); then
  echo "✅ Nix-Bash linter passed (0 shell fragment(s))"
  exit 0
fi

mapfile -t frags < <(find "$tmpdir" -type f -name '*.sh' | sort)

shfmt -i 2 -d "${frags[@]}"
shellcheck "${frags[@]}"
echo "✅ Nix-Bash linter passed (${#frags[@]} shell fragment(s))"
