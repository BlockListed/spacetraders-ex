defmodule Spacetraders.API do
  @moduledoc """
  # Spacetraders API
  """

  alias Spacetraders.API.Client

  def agent() do
    cvt(Client.agent())
  end

  def list_ships() do
    paginated(&Client.list_ships/1)
  end

  @spec get_ship(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_ship(ship) do
    res = cvt(Client.get_ship(ship))

    case res do
      {:ok, data} ->
        # sanity check
        true = data["nav"]["waypointSymbol"] == data["nav"]["route"]["destination"]["symbol"]
        {:ok, data}

      _ ->
        res
    end
  end

  def list_systems() do
    paginated(&Client.list_systems/1)
  end

  def get_system(system) do
    cvt(Client.get_system(system))
  end

  def list_waypoints(system) do
    paginated(&Client.list_waypoints(system, &1))
  end

  def list_filtered_waypoints(system, traits, type \\ nil) do
    paginated(&Client.list_filtered_waypoints(system, traits, type, &1))
  end

  def get_markets(system) do
    paginated(&Client.get_markets(system, &1))
  end

  def get_shipyards(system) do
    paginated(&Client.get_shipyards(system, &1))
  end

  def get_jump_gates(system) do
    paginated(&Client.get_jump_gates(system, &1))
  end

  def get_waypoint(waypoint) do
    case Spacetraders.API.Caching.Waypoints.get_waypoint(waypoint) do
      {:some, waypoint_info} ->
        {:ok, waypoint_info}

      :none ->
        res = cvt(Client.get_waypoint(waypoint))

        case res do
          {:ok, waypoint_info} ->
            Spacetraders.API.Caching.Waypoints.populate_waypoint(waypoint, waypoint_info)

          _ ->
            nil
        end

        res
    end
  end

  def get_market(waypoint) do
    cvt(Client.get_market(waypoint))
  end

  def get_shipyard(waypoint) do
    cvt(Client.get_shipyard(waypoint))
  end

  def get_jump_gate(waypoint) do
    cvt(Client.get_jump_gate(waypoint))
  end

  @spec orbit_ship(String.t()) :: any()
  def orbit_ship(ship) do
    cvt(Client.orbit_ship(ship))
  end

  @spec dock_ship(String.t()) :: any()
  def dock_ship(ship) do
    cvt(Client.dock_ship(ship))
  end

  def navigate_ship(ship, waypoint) do
    cvt(Client.navigate_ship(ship, waypoint))
  end

  def purchase_ship(shipyard, ship_type) do
    cvt(Client.purchase_ship(shipyard, ship_type))
  end

  def purchase_cargo(ship, symbol, units) do
    cvt(Client.purchase_cargo(ship, symbol, units))
  end

  def sell_cargo(ship, symbol, units) do
    cvt(Client.sell_cargo(ship, symbol, units))
  end

  def refuel_ship(ship, from_cargo \\ false) do
    cvt(Client.refuel_ship(ship, from_cargo))
  end

  def create_survey(ship) do
    cvt(Client.create_survey(ship))
  end

  def extract_resources(ship) do
    cvt(Client.extract_resources(ship))
  end

  def extract_resources_with_survey(ship, survey) do
    cvt(Client.extract_resources_with_survey(ship, survey))
  end

  def siphon_resources(ship) do
    cvt(Client.siphon_resources(ship))
  end

  def jettison_cargo(ship, symbol, units) do
    cvt(Client.jettison_cargo(ship, symbol, units))
  end

  def transfer_cargo(from_ship, to_ship, symbol, units) do
    cvt(Client.transfer_cargo(from_ship, to_ship, symbol, units))
  end

  def patch_nav(ship, flight_mode) do
    cvt(Client.patch_nav(ship, flight_mode))
  end

  defp cvt({_, %Tesla.Env{}} = resp) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <- resp do
      {:ok, body["data"]}
    else
      {:ok, resp} -> error(resp)
    end
  end

  defp paginated(f, after_page \\ 0, acc \\ []) when is_function(f, 1) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           f.(after_page + 1) do
      meta = body["meta"]

      is_last = meta["total"] <= meta["page"] * meta["limit"]

      page = body["data"] |> Enum.reverse()

      if is_last do
        all = Enum.concat(page, acc)
        {:ok, Enum.reverse(all)}
      else
        paginated(f, after_page + 1, Enum.concat(page, acc))
      end
    else
      {:ok, resp} -> error(resp)
    end
  end

  defp error(%Tesla.Env{} = resp) do
    status = resp.status
    body = resp.body["error"]["message"]

    {:error, "#{status} - #{body}"}
  end

  @spec distance_between(String.t(), String.t()) :: number()
  def distance_between(wp1_sym, wp2_sym) when is_binary(wp1_sym) and is_binary(wp2_sym) do
    {:ok, wp1} = get_waypoint(wp1_sym)
    {:ok, wp2} = get_waypoint(wp2_sym)

    {x1, y1} = {wp1["x"], wp1["y"]}
    {x2, y2} = {wp2["x"], wp2["y"]}

    dx = x2 - x1
    dy = y2 - y1

    :math.sqrt(dx * dx + dy * dy)
  end

  @spec closest_waypoint(Enumerable.t(String.t()), String.t()) :: String.t()
  def closest_waypoint(waypoints, to) do
    Enum.min_by(waypoints, &distance_between(to, &1))
  end

  def extract_system(waypoint) do
    [system_one, system_two, _] = String.split(waypoint, "-")

    Enum.join([system_one, system_two], "-")
  end
end

defmodule Spacetraders.Cooldown do
  @spec transit_end(map()) :: {:some, DateTime.t()} | :none
  def transit_end(data) do
    if Map.has_key?(data, "nav") do
      # call this function using the nav object
      transit_end(data["nav"])
    else
      if data["status"] == "IN_TRANSIT" do
        {:ok, transit_end, _} = DateTime.from_iso8601(data["route"]["arrival"])

        {:some, transit_end}
      else
        :none
      end
    end
  end

  @spec cooldown_end(map()) :: {:some, DateTime.t()} | :none
  def cooldown_end(data) do
    if Map.has_key?(data, "cooldown") do
      # call this function using the cooldown object
      cooldown_end(data["cooldown"])
    else
      if Map.has_key?(data, "expiration") do
        {:ok, cooldown_end, _} = DateTime.from_iso8601(data["expiration"])

        {:some, cooldown_end}
      else
        :none
      end
    end
  end

  @spec latest_wait_end(map()) :: {:some, DateTime.t()} | :none
  def latest_wait_end(data) do
    transit_end = transit_end(data)
    cooldown_end = cooldown_end(data)

    case {transit_end, cooldown_end} do
      {{:some, t_end}, {:some, c_end}} ->
        if DateTime.after?(t_end, c_end) do
          {:some, t_end}
        else
          {:some, c_end}
        end

      {{:some, t_end}, :none} ->
        {:some, t_end}

      {:none, {:some, c_end}} ->
        {:some, c_end}

      {:none, :none} ->
        :none
    end
  end

  def ms_until(datetime) do
    now = DateTime.now!("Etc/UTC")

    DateTime.diff(datetime, now, :millisecond)
  end

  def cooldown_ms(data) do
    latest_end = latest_wait_end(data)

    now = DateTime.now!("Etc/UTC")

    cd = with {:some, l_end} <- latest_end do
      DateTime.diff(l_end, now) 
    else
      _ -> 0
    end

    if cd > 0 do
      cd + 100
    else
      0
    end
  end
end
