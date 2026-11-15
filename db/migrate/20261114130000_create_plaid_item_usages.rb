class CreatePlaidItemUsages < ActiveRecord::Migration[8.1]
  def change
    # plaid_item_id has no foreign key: Plaid bills for items that were later
    # deleted, so the row must outlive the item.
    create_table :plaid_item_usages, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, index: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: true, type: :uuid, index: false, foreign_key: { on_delete: :nullify }
      t.uuid :plaid_item_id, null: false
      t.string :period, null: false
      t.string :institution_name
      t.string :plaid_region, null: false, default: "us"
      t.string :billed_products, array: true, null: false, default: []
      t.integer :transactions_refresh_count, null: false, default: 0

      t.timestamps
    end

    add_index :plaid_item_usages, [ :plaid_item_id, :period ], unique: true
    add_index :plaid_item_usages, [ :family_id, :period ]
    add_index :plaid_item_usages, [ :user_id, :period ]
  end
end
