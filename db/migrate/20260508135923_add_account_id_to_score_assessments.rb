# frozen_string_literal: true

class AddAccountIdToScoreAssessments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :score_assessments, :account, null: true, index: { algorithm: :concurrently }
  end
end
