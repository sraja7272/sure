module ConnectorsHelper
  # Whether a super admin has left this connector on. Views use it to hide
  # buttons that start a new connection (Provider::ConnectorAvailability).
  def connector_enabled?(key)
    Provider::ConnectorAvailability.enabled?(key)
  end

  def connector_kind_title(kind)
    case kind
    when "Bank" then t("admin.connectors.show.kinds.bank")
    when "Investment" then t("admin.connectors.show.kinds.investment")
    when "Crypto" then t("admin.connectors.show.kinds.crypto")
    end
  end
end
