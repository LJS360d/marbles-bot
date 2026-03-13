defmodule MarblesWeb.PageControllerTest do
  use MarblesWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Marbles"
    assert html =~ "Log in"
  end
end
