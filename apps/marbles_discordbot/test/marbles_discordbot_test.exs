defmodule MarblesDiscordbotTest do
  use ExUnit.Case
  doctest MarblesDiscordbot

  test "greets the world" do
    assert MarblesDiscordbot.hello() == :world
  end
end
