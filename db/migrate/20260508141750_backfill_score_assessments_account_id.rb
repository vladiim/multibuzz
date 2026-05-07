# frozen_string_literal: true

class BackfillScoreAssessmentsAccountId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    return if Rails.env.test?

    result = Score::AccountBackfillService.new.call
    say "Score assessment backfill: #{result.except(:success).inspect}"
  end

  def down
    # No-op: this is a forward-only data migration. Rolling back the schema FK
    # is handled by the prior migrations.
  end
end
