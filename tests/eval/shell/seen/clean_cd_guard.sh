#!/usr/bin/env bash
build() {
  cd "$1" || exit 1   # NEAR-MISS: looks like the cd bug, but guarded with || exit
  rm -rf ./out
}
