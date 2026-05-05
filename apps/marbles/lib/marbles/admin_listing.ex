defmodule Marbles.AdminListing do
  @moduledoc false

  @spec page_bounds(keyword(), pos_integer()) :: {pos_integer(), pos_integer(), non_neg_integer()}
  def page_bounds(opts, default_per_page) when is_list(opts) and is_integer(default_per_page) do
    page = Keyword.get(opts, :page, 1) |> max(1)
    per = Keyword.get(opts, :per_page, default_per_page)
    offset = (page - 1) * per
    {page, per, offset}
  end

  @spec trimmed_query(keyword()) :: String.t()
  def trimmed_query(opts) when is_list(opts) do
    Keyword.get(opts, :q, "") |> to_string() |> String.trim()
  end
end
