def load_config(path)
  File.read(path)
rescue
  nil  # cat#2: bare rescue swallows StandardError; caller never learns it failed
end
