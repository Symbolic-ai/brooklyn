defmodule BrooklynTest do
  use ExUnit.Case
  doctest Brooklyn

  test "greets the world" do
    assert Brooklyn.hello() == :world
  end
end
