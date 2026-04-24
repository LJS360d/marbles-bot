defmodule MarblesWeb.PageControllerTest do
  use MarblesWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Marbles"
    assert html =~ "Log in"
    assert html =~ ~s(href="/privacy-policy")
    assert html =~ ~s(href="/terms-of-service")
  end

  test "GET /privacy-policy", %{conn: conn} do
    conn = get(conn, ~p"/privacy-policy")
    assert html_response(conn, 200) =~ "Privacy Policy"
  end

  test "GET /terms-of-service", %{conn: conn} do
    conn = get(conn, ~p"/terms-of-service")
    assert html_response(conn, 200) =~ "Terms of Service"
  end
end
