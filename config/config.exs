import Config

config :tesla, :adapter, {Tesla.Adapter.Finch, name: Spacetraders.Finch}

config :logger, level: :info, handle_sasl_reports: true

config :logger, :default_formatter, metadata: [:file, :line, :pid]
