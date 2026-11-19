# Instance-wide switches for which account connectors users may start new
# connections with. A super admin manages them from Admin::ConnectorsController.
#
# Only the *offer* is gated: a connector that is switched off disappears from
# the connect flows and the "available" list on the Bank sync page, and its
# new-connection endpoints refuse requests (see ConnectorGated). Connections
# that already exist keep syncing and stay manageable.
#
# Stored as the list of *enabled* keys in Setting.enabled_connectors. Until a
# super admin first saves a choice the setting is unset and every connector is
# on; after that, only the listed connectors are on, so a connector added by a
# later release stays off until someone switches it on.
class Provider::ConnectorAvailability
  class Error < StandardError; end
  class NoneEnabledError < Error; end
  class UnknownConnectorError < Error; end

  Connector = Data.define(:key, :name, :kind)

  # Configuration-registry keys that share another connector's switch.
  # Plaid EU only holds EU credentials; its items are PlaidItems.
  KEY_ALIASES = { "plaid_eu" => "plaid" }.freeze

  KINDS = %w[Bank Investment Crypto].freeze

  LOCK_KEY = Zlib.crc32("provider_connector_availability")

  # Pages tracked for save ordering; the oldest are dropped beyond this.
  MAX_TRACKED_PAGES = 50

  class << self
    # Every connector, sorted by name. Adapters register when they load and
    # don't change at runtime, so the list is built once per class load.
    # @return [Array<Connector>]
    def all
      @all ||= Provider::Factory.registered_provider_types.filter_map do |provider_type|
        key = key_for_provider_type(provider_type)
        next if key.blank?

        meta = Provider::Metadata.for(key)
        kind = Array(meta[:kinds]).first.presence_in(KINDS) || "Bank"
        Connector.new(key: key, name: meta[:name] || key.titleize, kind: kind)
      end.uniq(&:key).sort_by { |c| c.name.downcase }.freeze
    end

    def keys
      @keys ||= all.map(&:key).freeze
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

    # Keys that aren't connectors (nothing to switch) are always on.
    def enabled?(key)
      saved = saved_enabled_keys
      return true if saved.nil?

      key = normalize_key(key)
      saved.include?(key) || !keys.include?(key)
    end

    def enabled_keys
      saved = saved_enabled_keys
      saved.nil? ? keys : keys & saved
    end

    # Replaces the set of enabled connectors. At least one must stay on.
    #
    # The Connectors page saves batched changes in the background, so saves can
    # overlap. Each one names its page (client_id) and a counter (sequence); a
    # save older than the newest one applied from the same page is ignored.
    # Each save carries the page's full state, so with two pages open the last
    # save wins, which is acceptable for a super-admin setting.
    #
    # @param enabled [Array<String>] connector keys to leave on
    # @return [Boolean] false when the save was ignored as out of date
    def update!(enabled, client_id: nil, sequence: nil)
      enabled = Array(enabled).map { |k| normalize_key(k) }.uniq
      unknown = enabled - keys
      raise UnknownConnectorError, "Unknown connectors: #{unknown.join(', ')}" if unknown.any?
      raise NoneEnabledError, "At least one connector must stay enabled" if enabled.empty?

      Setting.transaction do
        Setting.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
        Setting.clear_cache

        sequences = Setting.connectors_save_sequences.to_h.transform_keys(&:to_s)

        if client_id.present? && sequence.to_i <= sequences[client_id.to_s].to_i
          false
        else
          if client_id.present?
            sequences.delete(client_id.to_s)
            sequences[client_id.to_s] = sequence.to_i
            Setting.connectors_save_sequences = sequences.to_a.last(MAX_TRACKED_PAGES).to_h
          end
          Setting.enabled_connectors = enabled
          true
        end
      end
    end

    private
      def saved_enabled_keys
        saved = Setting.enabled_connectors
        saved&.map(&:to_s)
      end
  end
end
