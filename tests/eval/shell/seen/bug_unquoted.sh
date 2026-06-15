#!/usr/bin/env bash
copy() {
  cp $1 $2   # quoting: unquoted args word-split/glob on spaces (SC2086)
}
