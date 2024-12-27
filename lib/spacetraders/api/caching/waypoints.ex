defmodule Spacetraders.API.Caching.Waypoints do
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [&init_table/0]}
    }
  end

  def init_table() do
    :dets.open_file(__MODULE__, file: ~c"./caches/waypoint_cache.dets", type: :set)
    Process.sleep(:infinity)
  end

  def get_waypoint(waypoint) do
    case :dets.lookup(__MODULE__, waypoint) do
      [{_, waypoint_info}] -> {:some, waypoint_info}
      _ -> :none
    end
  end

  def populate_waypoint(waypoint, waypoint_info) do
    :dets.insert(__MODULE__, [{waypoint, waypoint_info}])
  end
end
