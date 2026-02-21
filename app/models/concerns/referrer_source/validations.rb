# frozen_string_literal: true

module ReferrerSource::Validations
  extend ActiveSupport::Concern

  included do
    validates :domain, presence: true, uniqueness: true
    validates :source_name, presence: true
    validates :medium, presence: true, inclusion: { in: ReferrerSources::Mediums::ALL }
    validates :data_origin, presence: true, inclusion: { in: ReferrerSources::DataOrigins::ALL }
  end
end
