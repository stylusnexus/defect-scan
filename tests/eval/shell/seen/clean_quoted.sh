#!/usr/bin/env bash
copy() {
  cp "$1" "$2"   # correct: quoted args, no word-splitting
}
