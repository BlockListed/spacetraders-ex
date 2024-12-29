defmodule Spacetraders.Bot.MarketChecker do
  alias Spacetraders.API
  use GenServer

  defmodule State do
    defstruct to_check: [], waiting: []

    @type t :: %State{to_check: [String.t()], waiting: [{String.t(), GenServer.from()}]}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_init_arg) do
    {:ok, %State{}}
  end

  def get_market(server, current_location) do
    # We could be waiting for a while
    GenServer.call(server, {:get, current_location}, :infinity)
  end

  def check_market(server, market) do
    GenServer.cast(server, {:check, market})
  end

  def handle_cast({:check, market}, state) do
    market_system = API.extract_system(market)

    if !Enum.empty?(state.waiting) do
      {closest_ship, _dist} =
        state.waiting
        |> Stream.filter(&(market_system == API.extract_system(elem(&1, 0))))
        |> Enum.reduce({nil, :infinity}, fn {ship_loc, _} = ship, {_, curr_dist} = acc ->
          new_dist = API.distance_between(ship_loc, market)

          cond do
            market == ship_loc -> acc
            curr_dist == :infinity -> {ship, new_dist}
            new_dist < curr_dist -> {ship, new_dist}
          end
        end)

      # assertion
      true = closest_ship != nil

      {_, from} = closest_ship

      GenServer.reply(from, market)

      {:noreply, state}
    else
      if !Enum.member?(state.to_check, market) do
        state = struct!(state, to_check: [market | state.to_check])

        {:noreply, state}
      else
        {:noreply, state}
      end
    end
  end

  def handle_call({:get, current_location}, from, state) do
    curr_system = API.extract_system(current_location)

    {closest_market, _dist} =
      state.to_check
      |> Stream.filter(&(curr_system == API.extract_system(&1)))
      |> Enum.reduce({nil, :infinity}, fn market, {curr_market, curr_dist} = acc ->
        new_dist = API.distance_between(current_location, market)

        cond do
          curr_market == current_location -> acc
          curr_dist == :infinity -> {market, new_dist}
          new_dist < curr_dist -> {market, new_dist}
        end
      end)

    case closest_market do
      nil ->
        state = struct!(state, waiting: [{current_location, from} | state.waiting])
        {:noreply, state}

      market ->
        state = struct!(state, to_check: state.to_check -- [market])
        {:reply, market, state}
    end
  end
end
