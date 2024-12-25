defmodule Spacetraders.API.RatelimitTest do
  use ExUnit.Case

  test "update_last_resets" do
    state = [
      %Spacetraders.API.Ratelimit{limit: 2, period_ms: 1000, consumed: 2},
      %Spacetraders.API.Ratelimit{limit: 30, period_ms: 61000, consumed: 5, last_reset_ms: System.os_time(:millisecond) + 100_000},
    ]

    [state_one, state_two] = Spacetraders.API.Ratelimit.test_update_last_resets(state)

    assert state_one.last_reset_ms > 0
    assert state_two.last_reset_ms > 0

    assert state_one.consumed == 0
    assert state_two.consumed == 5
  end
end
