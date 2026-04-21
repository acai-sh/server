defmodule AcaiWeb.Plausible do
  @schemes ["http", "https"]
  @inline_script "window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};plausible.init()"

  def inline_script do
    Phoenix.HTML.raw(@inline_script)
  end

  def src do
    case System.get_env("PLAUSIBLE_SRC") do
      nil -> nil
      value -> sanitize_src(value)
    end
  end

  def origin do
    case src() do
      nil ->
        nil

      src ->
        uri = URI.parse(src)

        default_port? =
          (uri.scheme == "https" and uri.port in [nil, 443]) or
            (uri.scheme == "http" and uri.port in [nil, 80])

        if default_port? do
          "#{uri.scheme}://#{uri.host}"
        else
          "#{uri.scheme}://#{uri.host}:#{uri.port}"
        end
    end
  end

  defp sanitize_src(value) when is_binary(value) do
    value = String.trim(value)

    case URI.parse(value) do
      %URI{scheme: scheme, host: host, userinfo: nil} = uri
      when scheme in @schemes and is_binary(host) and host != "" ->
        uri
        |> Map.put(:fragment, nil)
        |> Map.take([:scheme, :host, :port, :path, :query])
        |> then(&struct(URI, &1))
        |> URI.to_string()

      _ ->
        nil
    end
  end
end
