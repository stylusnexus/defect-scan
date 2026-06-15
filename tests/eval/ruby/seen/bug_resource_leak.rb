def first_line(path)
  f = File.open(path)  # cat#4: no block/ensure; handle leaks if readline raises
  f.readline.strip
end
