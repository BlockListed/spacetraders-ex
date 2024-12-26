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

  def get_ship(ship) do
    cvt(Client.get_ship(ship))
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

  def get_markets(system) do
    paginated(&Client.get_markets(system, &1))
  end

  def get_shipyards(system) do
    paginated(&Client.get_shipyards(system, &1))
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

  def orbit_ship(ship) do
    cvt(Client.orbit_ship(ship))
  end

  def dock_ship(ship) do
    cvt(Client.dock_ship(ship))
  end

  def navigate_ship(ship, waypoint) do
    cvt(Client.navigate_ship(ship, waypoint))
  end

  defp cvt({_, %Tesla.Env{}} = resp) do
    with {:ok, %Tesla.Env{status: 200, body: body}} <- resp do
      {:ok, body["data"]}
    else
      {:ok, resp} -> error(resp)
    end
  end

  defp paginated(f, after_page \\ 0, acc \\ []) when is_function(f, 1) do
    with {:ok, %Tesla.Env{status: 200, body: body}} <- f.(after_page + 1) do
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

  def cooldown_ms(data) do
    nav_wait =
      if Map.has_key?(data, "nav") do
        nav = data["nav"]

        if nav["status"] == "IN_TRANSIT" do
          {:ok, arrival, _} = DateTime.from_iso8601(nav["route"]["arrival"])
          now = DateTime.now!("Etc/UTC")

          DateTime.diff(arrival, now, :millisecond)
        else
          0
        end
      else
        0
      end

    cooldown_wait =
      if Map.has_key?(data, "cooldown") do
        cooldown = data["cooldown"]

        if Map.has_key?(cooldown, "expiration") do
          {:ok, expiration, _} = DateTime.from_iso8601(cooldown["expiration"])
          now = DateTime.now!("Etc/UTC")

          DateTime.diff(expiration, now, :millisecond)
        else
          0
        end
      else
        0
      end

    cd =
      [nav_wait, cooldown_wait]
      |> Enum.map(&if &1 < 0, do: 0, else: &1)
      |> Enum.max()

    if cd > 0 do
      cd + 100
    else
      cd
    end
  end
end
