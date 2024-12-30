defmodule Spacetraders.Market do
  alias Spacetraders.Model
  alias Spacetraders.API
  require Logger

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [&init_table/0]}
    }
  end

  def init_table() do
    :dets.open_file(__MODULE__, file: ~c"./caches/market_cache.dets", type: :set)

    Process.sleep(:infinity)
  end

  def enter_market_data(data) do
    if Map.has_key?(data, "tradeGoods") do
      curr_time = System.system_time(:millisecond)
      waypoint = data["symbol"]
      system = API.extract_system(waypoint)

      :dets.insert(__MODULE__, [{waypoint, data, system, curr_time}])
    else
      Logger.warning("Invalid market data submitted, no ship at market! #{inspect(data)}")
    end
  end

  @spec update_market_data(String.t()) :: :ok | {:error, String.t()}
  def update_market_data(symbol) do
    case API.get_market(symbol) do
      {:ok, market} ->
        enter_market_data(market)
        :ok

      res ->
        res
    end
  end

  def get(symbol) do
    case :dets.lookup(__MODULE__, symbol) do
      [{_, market, _, _}] -> {:some, market}
      [] -> :none
    end
  end

  def get_all() do
    :dets.foldr(fn val, acc -> [val | acc] end, [], __MODULE__)
    |> Enum.map(&elem(&1, 1))
  end

  def get_all_to_file(path) do
    all = get_all()

    File.write!(path, Jason.encode_to_iodata!(all))
  end

  def get_all_in_system(system) do
    :dets.match_object(__MODULE__, {:_, :_, system, :_})
    |> Stream.map(&elem(&1, 1))
    |> Enum.to_list()
  end

  def get_all_trades_for(system, symbol) do
    get_all_in_system(system)
    |> Stream.flat_map(fn market ->
      case Model.Market.get_trade(market, symbol) do
        {:some, trade} -> [{market["symbol"], trade}]
        :none -> []
      end
    end)
    |> Enum.to_list()
  end

  def highest_sell_price_for_in(system, symbol) do
    res =
      get_all_trades_for(system, symbol)
      |> Enum.max_by(&elem(&1, 1)["sellPrice"])

    case res do
      nil -> :none
      res -> {:some, res}
    end
  end

  def lowest_buy_price_for_in(system, symbol) do
    res =
      get_all_trades_for(system, symbol)
      |> Enum.min_by(&elem(&1, 1)["purchasePrice"])

    case res do
      nil -> :none
      res -> {:some, res}
    end
  end
end
