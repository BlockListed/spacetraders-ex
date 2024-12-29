defmodule Spacetraders.Model.Market do
  def get_trade(market, symbol) do
    case Enum.find(market["tradeGoods"], &(&1["symbol"] == symbol)) do
      nil -> :none
      trade -> {:some, trade}
    end
  end
end
