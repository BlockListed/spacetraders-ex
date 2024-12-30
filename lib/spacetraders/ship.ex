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
    [:state_functions, :state_enter]
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
      :none -> case Cooldown.cooldown_end(ship_data) do
        {:some, cooldown_end} ->
          state = %State{state | cooldown_end: cooldown_end}
          cd_time = Cooldown.ms_until(cooldown_end)

          {:ok, :cooldown, state, [{:state_timeout, cd_time, :elapsed}]}
        :none ->
          {:ok, :normal, state}
      end
    end
  end
end
