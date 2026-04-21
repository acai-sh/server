defmodule AcaiWeb.PlausibleTest do
  use ExUnit.Case, async: false

  defp restore_env(key, previous) do
    if is_nil(previous) do
      System.delete_env(key)
    else
      System.put_env(key, previous)
    end
  end

  test "returns a sanitized plausible src and origin for valid URLs" do
    previous = System.get_env("PLAUSIBLE_SRC")

    System.put_env(
      "PLAUSIBLE_SRC",
      " https://plausible.io/js/script.js?domain=app.acai.sh#ignored "
    )

    on_exit(fn -> restore_env("PLAUSIBLE_SRC", previous) end)

    assert AcaiWeb.Plausible.src() == "https://plausible.io/js/script.js?domain=app.acai.sh"
    assert AcaiWeb.Plausible.origin() == "https://plausible.io"
  end

  test "returns the inline plausible bootstrap script" do
    script = AcaiWeb.Plausible.inline_script() |> Phoenix.HTML.safe_to_string()

    assert script =~ "window.plausible=window.plausible||function()"
    assert script =~ "plausible.init()"
  end

  test "rejects invalid or dangerous plausible src values" do
    previous = System.get_env("PLAUSIBLE_SRC")

    on_exit(fn -> restore_env("PLAUSIBLE_SRC", previous) end)

    System.put_env("PLAUSIBLE_SRC", "javascript:alert(1)")
    assert is_nil(AcaiWeb.Plausible.src())
    assert is_nil(AcaiWeb.Plausible.origin())

    System.put_env("PLAUSIBLE_SRC", "https://user:pass@plausible.io/js/script.js")
    assert is_nil(AcaiWeb.Plausible.src())
    assert is_nil(AcaiWeb.Plausible.origin())
  end
end
