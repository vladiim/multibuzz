# frozen_string_literal: true

class AddScoreAssessmentsAccountFk < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_foreign_key :score_assessments, :accounts, validate: false
    validate_foreign_key :score_assessments, :accounts
  end
end
