import Config

config :tesla, :adapter, {Tesla.Adapter.Finch, name: Spacetraders.Finch}

config :logger, level: :info

config :logger, :default_formatter,
  metadata: [:file, :line, :pid]
