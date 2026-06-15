#!/usr/bin/env bash
run() {
  eval "$1"   # cat#3: eval on caller-supplied input -> command injection
}
