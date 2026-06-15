def first_line(path)
  File.open(path) { |f| f.readline.strip }  # correct: block form closes the handle
end
