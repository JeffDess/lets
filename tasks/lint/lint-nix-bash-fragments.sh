#!/usr/bin/env bash
set -euo pipefail

# Strict attr names that usually contain shell code in nixpkgs-style files.
ATTR_RE='(pre[a-zA-Z0-9_]*|post[a-zA-Z0-9_]*|[a-zA-Z0-9_]*Phase|shellHook|script|buildCommand|checkPhase|installCheckPhase|text)'

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
  awk -v file="$file" -v outdir="$tmpdir" -v attr_re="$ATTR_RE" -v start_n="$extract_count" '
      function leading_ws_len(s,    m) {
        match(s, /^[ \t]*/)
        return RLENGTH
      }

      function start_block(attr, line_no) {
        in_block = 1
        block_attr = attr
        block_start = line_no
        block_path = outdir "/" (++n) ".sh"
        block_line_count = 0
        block_base_indent = -1
        print "#!/usr/bin/env bash" > block_path
        print "# source: " file ":" block_start " attr=" block_attr >> block_path
      }

      function end_block() {
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
      }

      {
        line = $0

        if (!in_block) {
          # Match: attrName = two-single-quotes (allow whitespace)
          if (line ~ "^[[:space:]]*" attr_re "[[:space:]]*=[[:space:]]*\\047\\047[[:space:]]*$") {
            attr = line
            sub(/^[[:space:]]*/, "", attr)
            sub(/[[:space:]]*=.*/, "", attr)
            start_block(attr, NR)
          }
          next
        }

        # End of indented string marker + semicolon.
        if (line ~ /^[[:space:]]*\047\047[[:space:]]*;[[:space:]]*$/) {
          end_block()
          next
        }

        # Neutralize nix interpolation so shellcheck/shfmt can parse.
        gsub(/\$\{[^}]*\}/, "__NIX_INTERP__", line)
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
  echo "No shell fragments extracted"
  exit 0
fi

mapfile -t frags < <(find "$tmpdir" -type f -name '*.sh' | sort)

echo "Extracted ${#frags[@]} shell fragment(s)"
shfmt -i 2 -d "${frags[@]}"
shellcheck "${frags[@]}"
