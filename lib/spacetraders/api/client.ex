defmodule Spacetraders.API.Client do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.spacetraders.io/v2"


end
