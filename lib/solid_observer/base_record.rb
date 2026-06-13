# frozen_string_literal: true

module SolidObserver
  class BaseRecord < ActiveRecord::Base
    self.abstract_class = true
    # connects_to is configured by the engine after Rails initializes
  end
end
