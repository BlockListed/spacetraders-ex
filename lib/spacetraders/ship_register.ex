defmodule Spacetraders.ShipRegister do
  alias Spacetraders.API
  use GenServer

  defmodule State do
    defmodule Ship do
      @enforce_keys [:symbol, :location, :system, :role, :status]
      defstruct [:symbol, :location, :system, :role, :status]
    end

    defmodule Waiter do
      defstruct [:from, :system, :role]
    end

    defstruct ships: [], waiters: []
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def ship_role(ship) do
    case ship["registration"]["role"] do
      "SURVEYOR" -> :survey
      "EXCAVATOR" -> :miner
      _ -> nil
    end
  end

  def get_current_ships() do
    {:ok, ships} = API.list_ships()
  end

  def init(_init_arg) do
    {:ok, []}
  end
end
