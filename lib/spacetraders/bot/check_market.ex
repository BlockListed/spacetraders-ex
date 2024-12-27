defmodule Spacetraders.Bot.CheckMarkets.Manager do
  use GenServer

  alias Spacetraders.API

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    system = Keyword.fetch!(opts, :system)
    ship = Keyword.fetch!(opts, :ship)
    file = Keyword.get(opts, :file, "./markets.jsonl")

    opts =
      if name != nil do
        [name: name]
      else
        []
      end

    GenServer.start_link(__MODULE__, {system, ship, file}, opts)
  end

  @enforce_keys [:file, :to_check]
  defstruct [
    :file,
    :to_check,
    :system,
    checking: [],
    checked: []
  ]

  def init({system, ship, file}) do
    file = File.open!(file, [:append])

    {:ok, market_waypoints} = API.get_markets(system)

    markets = market_waypoints |> Enum.map(& &1["symbol"])

    {:ok, ship_data} = API.get_ship(ship) |> dbg

    case ship_data["nav"]["status"] do
      "DOCKED" ->
        {:ok, _} = API.orbit_ship(ship)

      "IN_TRANSIT" ->
        cooldown = API.cooldown_ms(ship_data) |> dbg
        Process.sleep(cooldown)

      "IN_ORBIT" ->
        nil
    end

    destination = ship_data["nav"]["route"]["destination"]

    server = self()

    {:ok, _} = Task.start_link(fn -> probe_code(server, ship, destination["symbol"]) end)

    {:ok, %__MODULE__{file: file, to_check: markets}}
  end

  defp get_market(server, curr) do
    GenServer.call(server, {:get_market, curr})
  end

  def progress(server) do
    GenServer.call(server, :progress)
  end

  defp deliver_market_data(server, market, data) do
    GenServer.cast(server, {:deliver_market_data, market, data})
  end

  def handle_call({:get_market, curr}, _, state) when is_binary(curr) do
    closest_market =
      state.to_check
      |> Stream.filter(&(&1 != curr))
      |> closest_market(curr)

    state = start_checking(state, closest_market)

    {:reply, closest_market, state}
  end

  def handle_call(:progress, _, state) do
    checked = Enum.count(state.checked)
    total_markets = Enum.count(state.to_check) + checked

    {:reply, "Checked #{checked} out of #{total_markets}!", state}
  end

  def handle_cast({:deliver_market_data, market, data}, state) do
    state = %{state | checking: state.checking -- [market]}
    state = %{state | checked: [market | state.checked]}

    info = %{
      "waypoint" => market,
      "data" => data
    }

    :ok = IO.binwrite(state.file, [Jason.encode_to_iodata!(info), "\n"])

    {:noreply, state}
  end

  @spec start_checking(%__MODULE__{}, String.t()) :: %__MODULE__{}
  defp start_checking(state, market) do
    state = %{state | to_check: state.to_check -- [market]}
    state = %{state | checking: [market | state.checking]}

    state
  end

  defp closest_market(markets, curr) do
    Enum.reduce(markets, {nil, :infinity}, fn new_market, {market, dist} ->
      new_dist = API.distance_between(curr, new_market)

      if market != nil do
        if new_dist < dist do
          {new_market, new_dist}
        else
          {market, dist}
        end
      else
        {new_market, new_dist}
      end
    end)
    |> elem(0)
  end

  defp probe_code(server, ship, curr) do
    next_market = get_market(server, curr)

    if next_market != curr do
      {:ok, res} = API.navigate_ship(ship, next_market) |> dbg

      Process.sleep(API.cooldown_ms(res))
    end

    {:ok, market_data} = API.get_market(next_market)

    deliver_market_data(server, next_market, market_data)

    probe_code(server, ship, next_market)
  end
end
