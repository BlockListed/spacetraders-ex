defmodule Spacetraders.Market do
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
      :dets.insert(__MODULE__, [{data["symbol"], data}])
    else
      Logger.warning("Invalid market data submitted, no ship at market! #{inspect(data)}")
    end
  end

  def get(symbol) do
    case :dets.lookup(__MODULE__, symbol) do
      [{_, market}] -> {:some, market}
      [] -> :none
    end
  end

  def get_all() do
    :dets.foldr(fn val, acc -> [val | acc] end, [], __MODULE__)
  end

  def get_all_to_file(path) do
    all = get_all() |> Enum.map(&elem(&1, 1))

    File.write!(path, Jason.encode_to_iodata!(all))
  end

  def get_all_in_system(system) do
    get_all()
    |> Stream.map(&elem(&1, 1))
    |> Stream.filter(&(API.extract_system(&1["symbol"]) == system))
    |> Enum.to_list()
  end
end
