# frozen_string_literal: true

class RerunJob < ApplicationRecord
  include RerunJob::Enums
  include RerunJob::Relationships
  include RerunJob::Validations
  include RerunJob::Scopes

  has_prefix_id :rjob
end
