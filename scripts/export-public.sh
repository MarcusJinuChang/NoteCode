#!/bin/zsh
# Copy the public snapshot of HEAD into a folder and scan it for what must
# not go public (docs/refactor/split.md › S3, step 1).
#
#   scripts/export-public.sh [<folder>]
#
# The folder must be empty or absent; the default is
# $TMPDIR/notecode-public/<worktree>-<hash>/export, emptied first. Only
# committed files are copied (`git archive HEAD`), so commit a change before
# exporting it. What goes is scripts/public-paths.txt, read from the working
# tree so a rule can be tried before it is committed; its header has the
# rule syntax. Whatever that file says, nothing under NEVER (below) is
# exported: a rule that would do so fails the run.
#
# Then the scans, every hit printed as `file:line: text`:
#  - gitleaks (`gitleaks detect --no-git`), if it is installed; it says so
#    if not (`brew install gitleaks`);
#  - a grep for each pattern in SCANS: the AdMob ids, the run proxy's URL,
#    the team id, the com.marcus bundle and product ids, the ad SDKs, email
#    addresses, local paths, prices, and the Pro test plan;
#  - every relative Markdown link to a file the export left out.
# Exits 0 when nothing is found, 1 when anything is, 2 when the export
# itself failed. The split expects 0 before the public repo is made.

set -uo pipefail
root=${0:A:h:h}
cd "$root" || exit 2

list=scripts/public-paths.txt
NEVER=(Pro/ NoteCode/Pro/ AppStore/ ProTests/ server/ docs/release-1.0/
       docs/site/ NoteCodeTests/Pro/ NoteCodeUITests/Pro/)

if (( $# > 0 )); then
  out=${1:A}
  if [[ -e $out && -n $(ls -A "$out" 2>/dev/null) ]]; then
    print -u2 "export-public: $out is not empty"; exit 2
  fi
else
  out=${TMPDIR:-/tmp}/notecode-public/${root:t}-$(print -rn -- "$root" | shasum | cut -c1-10)/export
  rm -rf "$out"
fi
mkdir -p "$out" || exit 2

# --- The rules ---
typeset -a rules maps_from maps_to
while IFS= read -r line || [[ -n $line ]]; do
  line=${line%%[[:space:]]#}                  # trailing space
  line=${line##[[:space:]]#}                  # leading space
  [[ -z $line || $line == \#* ]] && continue
  if [[ $line == *' => '* ]]; then
    maps_from+=(${line%% => *}) maps_to+=(${line##* => })
  else
    rules+=($line)
  fi
done < $list

# A path matches a rule when it is the rule, or the rule is a folder (ends
# in /) the path is inside.
matches() {  # rule path
  local r=$1 p=$2
  [[ $r == */ ]] && [[ $p == $r* ]] && return 0
  [[ $p == $r ]]
}
never() {  # path
  local n
  for n in $NEVER; do [[ $1 == $n* ]] && return 0; done
  return 1
}

files=(${(f)"$(git ls-tree -r --name-only HEAD)"})
typeset -A seen  # rules that matched something
chosen=() refused=()
for f in $files; do
  keep=0
  for r in $rules; do
    if [[ $r == !* ]]; then
      matches ${r#!} $f && { keep=0; seen[$r]=1; }
    else
      matches $r $f && { keep=1; seen[$r]=1; }
    fi
  done
  (( keep )) || continue
  if never $f; then refused+=($f); else chosen+=($f); fi
done

for (( i = 1; i <= $#maps_from; i++ )); do
  # Both ends: a map must not read a private file or write into a private place.
  { never ${maps_from[i]} || never ${maps_to[i]} } &&
    refused+=("${maps_from[i]} => ${maps_to[i]}")
done
if (( $#refused )); then
  print -u2 "export-public: public-paths.txt would export private paths:"
  print -u2 -l -- "  "$^refused
  exit 2
fi

# --- The copy ---
if (( $#chosen )); then
  git archive --format=tar HEAD -- $chosen | tar -x -C "$out" || exit 2
fi
mapped=0
for (( i = 1; i <= $#maps_from; i++ )); do
  src=${maps_from[i]} dst=${maps_to[i]}
  if ! git cat-file -e "HEAD:$src" 2>/dev/null; then
    print "absent at HEAD: $src (=> $dst)"; continue
  fi
  mkdir -p "$out/${dst:h}"
  git show "HEAD:$src" > "$out/$dst" || exit 2
  (( mapped++ ))
done
# A `!` rule that matches nothing is usually a path S2 has yet to make; only
# an including rule that matches nothing is worth saying.
for r in $rules; do
  [[ $r == !* ]] && continue
  (( ${+seen[$r]} )) || print "absent at HEAD: $r"
done
print "exported $(( $#chosen + mapped )) files of $(git rev-parse --short HEAD) to $out"

# --- The scans ---
hits=0
print "\n== gitleaks"
if command -v gitleaks >/dev/null; then
  gitleaks detect --no-git --source "$out" --no-banner --redact=0 -v
  (( $? == 0 )) || hits=1
else
  print "gitleaks is not installed (brew install gitleaks); not run"
fi

# label|extended regex. Tests use example.com and example.test addresses,
# and the app shows its support address, which is public; those are left
# out of the email scan.
SCANS=(
  'AdMob id|ca-app-pub-[0-9]+'
  'run proxy URL|notecode-run-proxy|workers\.dev'
  'team id|N454V8HV9J|DEVELOPMENT_TEAM *= *[A-Z0-9]{10}'
  'com.marcus id|com\.marcus\.'
  'ad SDK|GoogleMobileAds|google-mobile-ads|UserMessagingPlatform|google-user-messaging|GADApplicationIdentifier'
  'email address|[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)*\.(com|net|org|edu|io|dev|app|me|co|uk)([^A-Za-z0-9]|$)'
  'local path|/Users/[A-Za-z]|NoteCode-private'
  'price|\$[0-9]+\.[0-9]{2}'
  'Pro test plan|Pro\.xctestplan'
)
for scan in $SCANS; do
  label=${scan%%|*} pattern=${scan#*|}
  found=$(cd "$out" && grep -rnIE -- "$pattern" . | sed 's|^\./||' |
    { [[ $label == 'email address' ]] && grep -vE '@example\.(com|test)|notecodesupport@gmail\.com' || cat; } |
    cut -c1-220 | sort)
  lines=(${(f)found})
  print "\n== $label: $#lines"
  (( $#lines )) && { print -rl -- $lines; hits=1; }
done

# Relative links in the Markdown that lead to a file the export left out.
broken=()
for md in $out/**/*.md(N); do
  for target in ${(f)"$(grep -oE '\]\([^)#[:space:]]+' $md | cut -c3-)"}; do
    [[ $target == (http|https|mailto):* || $target == /* ]] && continue
    # Only paths: `[text](url)` in a note about link syntax is not one.
    [[ $target == */ || $target == *.(md|txt|swift|sh|html|png|json|plist|xcprivacy|storekit) ]] || continue
    [[ -e ${md:h}/$target ]] || broken+=("${md#$out/}: $target")
  done
done
print "\n== link to a file left out: $#broken"
(( $#broken )) && { print -rl -- ${(o)broken}; hits=1; }

print
(( hits )) && { print "export-public: hits above, in $out"; exit 1; }
print "export-public: clean, $out"
