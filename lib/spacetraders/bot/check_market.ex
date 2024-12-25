defmodule Spacetraders.Bot.CheckMarkets do
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

  @enforce_keys [:file, :ship_pid, :to_check, :positions]
  defstruct [:file, :ship_pid, :to_check, :positions, checked: []]

  def init({system, ship, file}) do
    file = File.open!(file, [:append])

    {:ok, market_waypoints} = API.get_markets(system)

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

    market_positions =
      Enum.reduce(market_waypoints, %{}, fn wp, acc ->
        Map.put(acc, wp["symbol"], {wp["x"], wp["y"]})
      end)
      |> Map.put(destination["symbol"], {destination["x"], destination["y"]})

    markets = market_waypoints |> Enum.map(& &1["symbol"])

    server = self()

    {:ok, ship_pid} = Task.start_link(fn -> probe_code(server, ship, destination["symbol"]) end)

    {:ok,
     %__MODULE__{file: file, to_check: markets, ship_pid: ship_pid, positions: market_positions}}
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
    pos = market_xy(state, curr)

    closest_market =
      state.to_check
      |> Stream.filter(&(&1 != curr))
      |> closest_market(state, pos)

    {:reply, closest_market, state}
  end

  def handle_call(:progress, _, state) do
    checked = Enum.count(state.checked)
    total_markets = Enum.count(state.to_check) + checked

    {:reply, "Checked #{checked} out of #{total_markets}!", state}
  end

  def handle_cast({:deliver_market_data, market, data}, state) do
    state = %{state | to_check: state.to_check -- [market]}
    state = %{state | checked: [market | state.checked]}

    info = %{
      "waypoint" => market,
      "data" => data,
    }

    :ok = IO.binwrite(state.file, [JSON.encode_to_iodata!(info), "\n"])

    {:noreply, state}
  end

  defp market_xy(state, market) do
    Map.fetch!(state.positions, market)
  end

  defp closest_market(markets, state, {x, y}) do
    Enum.reduce(markets, {nil, :infinity}, fn new_market, {market, dist} ->
      {n_x, n_y} = market_xy(state, new_market)

      new_dist = :math.sqrt(Integer.pow(n_x - x, 2) + Integer.pow(n_y - y, 2))

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
    next_market = get_market(server, curr) |> dbg

    if next_market != curr do
      {:ok, res} = API.navigate_ship(ship, next_market) |> dbg

      Process.sleep(API.cooldown_ms(res))
    end

    {:ok, market_data} = API.get_market(next_market)

    deliver_market_data(server, next_market, market_data)

    probe_code(server, ship, next_market)
  end
end
