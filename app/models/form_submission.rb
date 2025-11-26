class FormSubmission < ApplicationRecord
  include FormSubmission::Validations
  include FormSubmission::Scopes

  has_prefix_id :form

  enum :status, { pending: 0, contacted: 1, completed: 2, spam: 3 }

  store_accessor :data
end
