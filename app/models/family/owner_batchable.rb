# Splits an AI enrichment batch by account owner and makes one provider request
# per owner, so each request, and the usage row it records, is charged to the
# person whose accounts it covered. Ownerless accounts form one group with a nil
# owner. The including class defines `scope`, the transactions to send.
module Family::OwnerBatchable
  private
    def transactions_by_owner
      groups = scope.includes(entry: :account).group_by { |transaction| transaction.entry.account.owner_id }
      owners = User.where(id: groups.keys.compact).index_by(&:id)
      groups.transform_keys { |owner_id| owners[owner_id] }
    end

    # Yields each owner with their transactions and collects the responses'
    # data. Stops at the first failed request and returns a failed response
    # whose data holds what the earlier requests returned, so the caller can
    # still apply answers that were already paid for.
    def request_per_owner
      collected = []

      transactions_by_owner.each do |owner, transactions|
        response = yield(owner, transactions)
        return Provider::Response.new(success?: false, data: collected, error: response.error) unless response.success?

        collected.concat(response.data)
      end

      Provider::Response.new(success?: true, data: collected, error: nil)
    end
end
