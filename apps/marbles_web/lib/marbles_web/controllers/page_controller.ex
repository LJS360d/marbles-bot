defmodule MarblesWeb.PageController do
  use MarblesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
