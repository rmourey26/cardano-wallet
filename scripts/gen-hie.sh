#!/usr/bin/env bash

######################################################################
# Generates a "direct" cradle config for ghcide. Use this if you want
# faster reloads and cross-package jump-to-definition. It needs to be
# run from the nix-shell.
######################################################################

out=hie-direct.yaml
ghci=custom.ghci
builddir=dist-newstyle

set -euo pipefail

######################################################################
# Functions for querying Cabal projects

plan_json=$builddir/cache/plan.json
mapfile -t packages < <(git ls-files '*.cabal' | xargs basename -a | sed 's/\.cabal//')
version=$(awk '/^version:/ { print $2; }' "$(git ls-files '*.cabal' | head -n1)")

list_sources() {
  git ls-files 'lib/**/*.hs' | grep -v Main.hs
}

# usage: query_plan_json PACKAGE COMP:NAME KEY
query_plan_json() {
  jq -r '.["install-plan"][]|select(."pkg-name"=="'"$1"'")|select(.["component-name"]=="'"$2"'")["'"$3"'"]' < $plan_json
}

# usage: get_dist_dir PACKAGE
get_dist_dir() {
  relpath "$(query_plan_json "$1" lib dist-dir)"
}

# usage: get_bin_dir PACKAGE exe:NAME
get_bin_dir() {
  dirname "$(relpath "$(query_plan_json "$1" "$2" bin-file)")"
}

relpath() {
  # path must exist
  # realpath "--relative-to=$(pwd)" "$1"
  # shellcheck disable=SC2001
  echo "$1" | sed "s=$(pwd)/=="
}

setup_cabal_plan() {
  test -f $plan_json || cabal --project-file=cabal-nix.project "--builddir=$builddir" configure
}

######################################################################
# Config file generation

gen_header() {
  echo "$1 Generated by $0 for version $version"
  echo "$1 $(date)"
  echo
}

make_hie() {
  gen_header \#

  cat <<EOF
cradle:
  multi:
    - path: "./lib"
      config:
        cradle:
          direct:
            arguments:
              - -XOverloadedStrings
              - -XNoImplicitPrelude
              - -XTypeApplications
              - -XDataKinds
              - -fwarn-unused-binds
              - -fwarn-unused-imports
              - -fwarn-orphans
              - -Wno-missing-home-modules
EOF

  mapfile -t sources < <(list_sources)
  dirname "${sources[@]}" | sed -e 's/^\([^A-Z]*\).*$/              - -i\1/' | sed 's=/$==' | sort -u
  list_sources | sed -e 's/^[^A-Z]*\(.*\)\.hs$/\1/' | grep / | sed 'y=/=.=' | sed 's/^/              - /'

  for pkg in "${packages[@]}"; do
    echo "              - Paths_$(echo "$pkg" | sed y/-/_/)"
    echo "              - -i$(get_dist_dir "$pkg")/build/autogen"
  done

  cat <<EOF

    - path: "."
      config: {cradle: {none: }}
EOF
}

make_ghci() {
  gen_header --

  cat <<EOF
:set prompt "λ "
:set -fwarn-unused-binds
:set -fwarn-unused-imports
:set -Wno-missing-home-modules
:set -XOverloadedStrings
:set -XNoImplicitPrelude
:set -XTypeApplications -XDataKinds

import Prelude
import System.Environment (setEnv, getEnv)
import System.Directory (getCurrentDirectory)

getCurrentDirectory >>= \d -> getEnv "PATH" >>= \p -> setEnv "PATH" (d ++ "$(get_bin_dir cardano-wallet exe:cardano-wallet):" ++ p)

EOF

  list_sources | grep -v Main.hs | xargs dirname | sed -e 's/^\([^A-Z]*\).*$/:set -i\1/' | sed 's=/$==' | sort -u

  for pkg in "${packages[@]}"; do
    echo ":set -i$(get_dist_dir "$pkg")/build/autogen"
  done
}

######################################################################
# Main script

echo "Generating $out. Some cabal builds may be necessary."

setup_cabal_plan

make_hie > $out

make_ghci > $ghci

echo "Finished. Type the following to enable your config:"
echo "  ln -sf $out hie.yaml"
echo "  ln -sf $ghci .ghci"
