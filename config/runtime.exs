import Config
import Dotenvy

source!([".env", System.get_env()])

config :spacetraders, :token, env!("TOKEN")
