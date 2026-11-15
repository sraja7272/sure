# Instance-wide switches for which account connectors users may start new
# connections with. A super admin manages them from Admin::ConnectorsController.
#
# Only the *offer* is gated: a connector that is switched off disappears from
# the connect flows and the "available" list on the Bank sync page, and its
# new-connection endpoints refuse requests (see ConnectorGated). Connections
# that already exist keep syncing and stay manageable.
#
# Stored as the list of *disabled* keys in Setting.disabled_connectors, so an
# empty setting -- the default -- means every connector is on.
class Provider::ConnectorAvailability
  class Error < StandardError; end
  class NoneEnabledError < Error; end
  class UnknownConnectorError < Error; end

  Connector = Data.define(:key, :name, :kind)

  # Configuration-registry keys that share another connector's switch.
  # Plaid EU only holds EU credentials; its items are PlaidItems.
  KEY_ALIASES = { "plaid_eu" => "plaid" }.freeze

  # Display names for connectors whose Provider::Metadata entry has no :name.
  NAMES = {
    "akahu" => "Akahu", "binance" => "Binance", "brex" => "Brex", "coinbase" => "Coinbase",
    "coinstats" => "CoinStats", "enable_banking" => "Enable Banking", "ibkr" => "Interactive Brokers",
    "indexa_capital" => "Indexa Capital", "kraken" => "Kraken", "lunchflow" => "Lunch Flow",
    "mercury" => "Mercury", "monobank" => "Monobank", "plaid" => "Plaid", "questrade" => "Questrade",
    "redbark" => "Redbark", "sharesight" => "Sharesight", "simplefin" => "SimpleFIN",
    "snaptrade" => "SnapTrade", "sophtron" => "Sophtron", "trade_republic" => "Trade Republic",
    "trading212" => "Trading 212", "up" => "Up", "wise" => "Wise"
  }.freeze

  KINDS = %w[Bank Investment Crypto].freeze

  class << self
    # Every connector, sorted by name.
    # @return [Array<Connector>]
    def all
      Provider::Factory.registered_provider_types.filter_map do |provider_type|
        key = key_for_provider_type(provider_type)
        next if key.blank?

        meta = Provider::Metadata.for(key)
        kind = Array(meta[:kinds]).first.presence_in(KINDS) || "Bank"
        Connector.new(key: key, name: meta[:name] || NAMES[key] || key.titleize, kind: kind)
      end.uniq(&:key).sort_by { |c| c.name.downcase }
    end

    def keys
      all.map(&:key)
    end

    # "PlaidAccount" => "plaid", "FinancekitAccountLineage" => "financekit"
    def key_for_provider_type(provider_type)
      provider_type.to_s.sub(/Account(Lineage)?\z/, "").underscore.presence
    end

    # Accepts connector keys and their aliases (e.g. "plaid_eu").
    def normalize_key(key)
      key = key.to_s
      KEY_ALIASES.fetch(key, key)
    end

    def enabled?(key)
      !disabled_keys.include?(normalize_key(key))
    end

    def disabled_keys
      Array(Setting.disabled_connectors).map(&:to_s)
    end

    def enabled_keys
      keys - disabled_keys
    end

    # Replaces the set of enabled connectors. At least one must stay on.
    # @param enabled [Array<String>] connector keys to leave on
    def update!(enabled)
      enabled = Array(enabled).map { |k| normalize_key(k) }.uniq
      unknown = enabled - keys
      raise UnknownConnectorError, "Unknown connectors: #{unknown.join(', ')}" if unknown.any?
      raise NoneEnabledError, "At least one connector must stay enabled" if enabled.empty?

      Setting.disabled_connectors = keys - enabled
    end
  end
end
