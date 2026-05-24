# frozen_string_literal: true

# Phase 5 shipped a single free-text scheduling_note. UAT showed customers
# need structure so the specialist can sort kickoff slots by timezone and
# availability. Replace the text column with a jsonb scheduling_preferences
# column shaped { timezone:, days:, time_blocks: }.
class ReplaceGuidedSetupSchedulingNoteWithPreferences < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      remove_column :guided_setups, :scheduling_note, if_exists: true
      add_column :guided_setups, :scheduling_preferences, :jsonb, default: {}, null: false
    end
  end

  def down
    safety_assured do
      remove_column :guided_setups, :scheduling_preferences, if_exists: true
      add_column :guided_setups, :scheduling_note, :text
    end
  end
end
