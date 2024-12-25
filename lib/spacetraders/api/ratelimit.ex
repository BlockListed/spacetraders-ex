defmodule Spacetraders.API.Ratelimit do
  use GenServer

  @enforce_keys [:limit, :period_ms]
  defstruct [:limit, :period_ms, consumed: 0, last_reset_ms: 0]

  def reserve(server) do
    # we might wait a while for our timeout
    GenServer.call(server, :reserve, :infinity) 
  end


  def start_link(opts) do
    limiters = Keyword.get(opts, :limiters, [])

    name = Keyword.get(opts, :name, nil)

    opts =
      if name != nil do
        [name: name]
      else
        []
      end

    GenServer.start_link(__MODULE__, limiters, opts)
  end

  def init(ratelimiters) do
    {:ok, ratelimiters}
  end

  def handle_call(:reserve, _, state) do
    if !Enum.empty?(state) do
      {:ok, state} = acquire(state)
      
      {:reply, :ok, state}
    else
      {:reply, :ok, state}
    end
  end

  defp acquire(state) do
    {state, wait} = acquire_now(state)
    if wait == 0 do
      {:ok, state}
    else
      # assertion
      false = wait == :infinity

      Process.sleep(wait) 
      acquire(state)
    end
  end

  defp acquire_now(state) do
    state = update_last_resets(state)

    {state, wait} = Enum.reduce(state, {[], :infinity}, fn(r, {state, wait}) ->
      if wait == 0 do
        {[r | state], wait}
      else
        if r.consumed < r.limit do
          r = %{r | consumed: r.consumed + 1}
          {[r | state], 0}
        else
          new_state = [r | state]

          cond do
            wait == :infinity -> {new_state, wait_time(r)}
            wait < wait_time(r) -> {new_state, wait}
            true -> {new_state, wait_time(r)}
          end 
        end 
      end 
    end)

    # assertion
    false = wait == :infinity

    {state |> Enum.reverse(), wait}
  end

  defp update_last_resets(state) do
    state
    |> Enum.map(fn r ->
      curr_time = curr_time_ms()
      
      if curr_time - r.last_reset_ms >= r.period_ms do
        %{%{r | consumed: 0} | last_reset_ms: curr_time }
      else
        r
      end
    end)
  end

  if Mix.env == :test do
    @doc """
    ONLY FOR TESTING, DO NOT USE
    """
    def test_update_last_resets(state) do
      update_last_resets(state)
    end
  end

  defp wait_time(%Spacetraders.API.Ratelimit{limit: l, consumed: c, period_ms: p, last_reset_ms: lr}) do
    # assertion
    true = l == c

    wait_time = (lr + p) - curr_time_ms()

    if wait_time < 0 do
      0
    else
      wait_time
    end
  end

  defp curr_time_ms() do
    System.os_time(:millisecond)
  end
end

defmodule Spacetraders.API.Ratelimit.Middleware do
  @behaviour Tesla.Middleware

  alias Spacetraders.API.Ratelimit

  def call(env, next, opts) do
    server = Keyword.fetch!(opts, :server)

    Ratelimit.reserve(server)

    Tesla.run(env, next)
  end
end
