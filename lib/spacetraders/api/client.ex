defmodule Spacetraders.API.Client do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.spacetraders.io/v2"
  plug Tesla.Middleware.BearerAuth, token: Application.fetch_env!(:spacetraders, :token)
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Retry,
    delay: 500,
    max_retries: 10,
    max_delay: 4_000,
    should_retry: fn 
      {:ok, %{status: status}} when status == 429 -> true
      _ -> false
    end

  plug Spacetraders.API.Ratelimit.Middleware, server: Spacetraders.API.Ratelimit

  def agent() do
    get("/my/agent")
  end
end
