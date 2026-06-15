#!/usr/bin/env bash
run() {
  "$@"   # correct: invoke the argv directly, no eval
}
