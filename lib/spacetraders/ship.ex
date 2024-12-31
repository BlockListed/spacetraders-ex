defmodule Spacetraders.Ship do
  alias Spacetraders.Cooldown
  alias Spacetraders.API
  @behaviour :gen_statem

  def start_link(opts) do
    ship = Keyword.fetch!(opts, :ship)

    name = Keyword.get(opts, :name)

    if name != nil do
      :gen_statem.start_link({:local, name}, __MODULE__, ship, opts)
    else
      :gen_statem.start_link(__MODULE__, ship, opts)
    end
  end

  defmodule State do
    @enforce_keys [:ship, :nav, :cargo]
    defstruct [:ship, :nav, :cargo, cooldown_end: nil]
  end

  def callback_mode() do
    [:handle_event_function, :state_enter]
  end

  #            +-----------+                          
  # +--------->| Normal    +-------------------------+
  # |          +-----------+                         |
  # |                                                |
  # |                                                |
  # |   Arrive +-----------+                 Navigate|
  # +----------+ Transit   |<------------------------+
  # |          +-----------+                         |
  # |                ^                               |
  # |                |Navigate                       |
  # |  Expires +-----+-----+  Cooldown-causing Action|
  # +----------+ Cooldown  |<------------------------+
  #            +-----------+                          
  #
  # Yes, in the case of Cooldown->Transit we may
  # end up waiting to long, but I don't care.

  def init(ship) do
    {:ok, ship_data} = API.get_ship(ship)

    cargo = ship_data["cargo"]

    nav = ship_data["nav"]

    state = %State{ship: ship, nav: nav, cargo: cargo}

    case Cooldown.transit_end(ship_data) do
      {:some, transit_end} ->
        state = %State{state | cooldown_end: transit_end}
        cd_time = Cooldown.ms_until(transit_end)

        {:ok, :transit, state, [{:state_timeout, cd_time, :arrived}]}

      :none ->
        case Cooldown.cooldown_end(ship_data) do
          {:some, cooldown_end} ->
            state = %State{state | cooldown_end: cooldown_end}
            cd_time = Cooldown.ms_until(cooldown_end)

            {:ok, :cooldown, state, [{:state_timeout, cd_time, :elapsed}]}

          :none ->
            {:ok, :normal, state}
        end
    end
  end

  def update_cooldown(data, cooldown_end) do
    if data.cooldown_end == nil do
      %{data | cooldown_end: cooldown_end}
    else
      if DateTime.after?(cooldown_end, data.cooldown_end) do
        %{data | cooldown_end: cooldown_end}
      else
        data
      end
    end
  end

  def cooldown_and_reply(data, from, reply, cd) do
    data = update_cooldown(data, cd)

    wait_ms = Cooldown.ms_until(data.cooldown_end)

    {:next_state, :cooldown, data, [{:state_timeout, wait_ms, :elapsed}, {:reply, from, reply}]}
  end

  def handle_event(:enter, _old_state, new_state, data) do
    if new_state == :normal do
      data = %{data | cooldown_end: nil}

      {:keep_state, data}
    else
      {:keep_state_and_data}
    end
  end

  def handle_event(:state_timeout, :arrived, :transit, data) do
    {:next_state, :normal, data}
  end

  def handle_event(:state_timeout, :elapsed, :cooldown, data) do
    {:next_state, :normal, data}
  end

  def handle_event({:call, from}, :orbit, state, data) do
    if state in [:normal, :cooldown] do
      # we can't be IN_TRANSIT.
      if data.nav["status"] != "IN_ORBIT" do
        {:ok, nav} = API.orbit_ship(data.ship)

        data = %{data | nav: nav["nav"]}

        {:keep_state, data, [{:reply, from, nav}]}
      else
        {:keep_state_and_data, [{:reply, from, %{"nav" => data.nav}}]}
      end
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, :dock, state, data) do
    if state in [:normal, :cooldown] do
      # we can't be IN_TRANSIT
      if data.nav["status"] != "DOCKED" do
        {:ok, nav} = API.dock_ship(data.ship)

        data = %{data | nav: nav["nav"]}

        {:keep_state, data, [{:reply, from, nav}]}
      else
        {:keep_state_and_data, [{:reply, from, %{"nav" => data.nav}}]}
      end
    end
  end

  def handle_event({:call, from}, :survey, state, data) do
    if state == :normal do
      {:ok, res} = API.create_survey(data.ship)

      cd = Cooldown.cooldown_end(res)

      cooldown_and_reply(data, from, res, cd)
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, :extract, state, data) do
    if state == :normal do
      {:ok, res} = API.extract_resources(data.ship)

      cd = Cooldown.cooldown_end(res)

      data = %{data | cargo: res["cargo"]}

      cooldown_and_reply(data, from, res, cd)
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, {:extract, survey}, state, data) do
    if state == :normal do
      {:ok, res} = API.extract_resources_with_survey(data.ship, survey)

      cd = Cooldown.cooldown_end(res)

      data = %{data | cargo: res["cargo"]}

      cooldown_and_reply(data, from, res, cd)
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, :siphon, state, data) do
    if state == :normal do
      {:ok, res} = API.siphon_resources(data.ship)

      cd = Cooldown.cooldown_end(res)

      data = %{data | cargo: res["cargo"]}

      cooldown_and_reply(data, from, res, cd)
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, {:jettison, symbol, units}, state, data) do
    if state in [:normal, :cooldown] do
      {:ok, res} = API.jettison_cargo(data.ship, symbol, units)

      data = %{data | cargo: res["cargo"]}

      {:keep_state, data, [{:reply, from, res}]}
    else
      {:keeP_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, {:navigate, wp}, state, data) do
    if state in [:normal, :cooldown] do
      if wp != data.nav["waypointSymbol"] do
        {:ok, nav} = API.navigate_ship(data.ship, wp)

        cooldown_end = Cooldown.transit_end(nav)

        data = %{data | nav: nav["nav"]}
        data = update_cooldown(data, cooldown_end)

        wait_ms = Cooldown.ms_until(data.cooldown_end)

        {:next_state, :navigate, data, [{:state_timeout, wait_ms, :arrived}, {:reply, from, nav}]}
      else
        {:keep_state_and_data, [{:reply, from, %{"nav" => data.nav}}]}
      end
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, {:patch, flight_mode}, state, data) do
    if state in [:normal, :cooldown] do
      # for some reason in this case nav is the top-level
      # object.
      {:ok, nav} = API.patch_nav(data.ship, flight_mode)

      # see above comment
      data = %{data | nav: nav}

      {:keep_state, data, [{:reply, from, nav}]}
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, {:sell, symbol, units}, state, data) do
    if state in [:normal, :cooldown] do
      {:ok, res} = API.sell_cargo(data.ship, symbol, units)

      data = %{data | cargo: res["cargo"]}

      {:keep_state, data, [{:reply, from, res}]}
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, {:purchase, symbol, units}, state, data) do
    if state in [:normal, :cooldown] do
      {:ok, res} = API.purchase_cargo(data.ship, symbol, units)

      data = %{data | cargo: res["cargo"]}

      {:keep_state, data, [{:reply, from, res}]}
    else
      {:keep_state_and_data, [:postpone]}
    end
  end

  def handle_event({:call, from}, :refuel, state, data) do
    if state in [:normal, :cooldown] do
      {:ok, res} = API.refuel_ship(data.ship)

      {:keep_state_and_data, [{:reply, from, res}]}
    else
      {:keep_state_and_data, [:postpone]}
    end
  end
  
  def handle_event({:call, from}, {:transfer, from_ship, to_ship, symbol, units}, state, data) do
    if state in [:normal, :cooldown] do
      raise "Unimplemented"
    else
      {:keep_state_and_data, [:postpone]}
    end
  end
end
