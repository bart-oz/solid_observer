# frozen_string_literal: true

module SolidObserver
  class BaseEvent < ActiveRecord::Base
    self.abstract_class = true
  end
end
