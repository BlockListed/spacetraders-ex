import Config

config :tesla, :adapter, {Tesla.Adapter.Finch, name: Spacetraders.Finch}

config :logger, level: :info
