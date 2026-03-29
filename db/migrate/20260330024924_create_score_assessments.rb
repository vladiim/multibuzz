# frozen_string_literal: true

class CreateScoreAssessments < ActiveRecord::Migration[8.0]
  def change
    create_table :score_assessments do |t|
      t.references :user, null: true, foreign_key: true
      t.float :overall_score, null: false
      t.integer :overall_level, null: false
      t.jsonb :dimension_scores, null: false, default: {}
      t.jsonb :answers, null: false, default: []
      t.jsonb :context, null: false, default: {}
      t.string :source
      t.jsonb :utm_params, default: {}
      t.string :claim_token
      t.timestamps
    end

    add_index :score_assessments, :claim_token, unique: true, where: "claim_token IS NOT NULL"
    add_index :score_assessments, :overall_level
    add_index :score_assessments, :created_at

    create_table :score_teams do |t|
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :invite_slug, null: false
      t.integer :member_count, null: false, default: 1
      t.float :alignment_score
      t.timestamps
    end

    add_index :score_teams, :invite_slug, unique: true

    create_table :score_team_memberships do |t|
      t.references :score_team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :score_assessment, null: false, foreign_key: true
      t.string :role_label
      t.datetime :joined_at, null: false
      t.timestamps
    end

    add_index :score_team_memberships, [ :score_team_id, :user_id ], unique: true
  end
end
