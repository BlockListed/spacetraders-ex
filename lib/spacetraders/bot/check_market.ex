defmodule Spacetraders.Bot.CheckMarkets do
  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
  end
end
