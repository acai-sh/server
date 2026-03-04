defmodule AcaiWeb.UserSessionHTML do
  use AcaiWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:acai, Acai.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
