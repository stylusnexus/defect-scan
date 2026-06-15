def load(path)
  File.read(path)
rescue
  nil
end
