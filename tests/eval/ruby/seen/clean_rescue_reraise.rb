def load_config(path)
  File.read(path)
rescue => e          # NEAR-MISS: looks like a swallow, but logs and re-raises
  Rails.logger.error(e)
  raise
end
