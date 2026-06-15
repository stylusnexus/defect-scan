#!/usr/bin/env bash
build() {
  cd "$1"          # cat#2: no || exit; a failed cd runs the rest in the wrong dir (SC2164)
  rm -rf ./out
}
