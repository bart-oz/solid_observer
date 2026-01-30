# frozen_string_literal: true

module SolidObserver
  class BaseEvent < ActiveRecord::Base
    self.abstract_class = true

    # connects_to is configured by the engine after Rails initializes
    # See lib/solid_observer/engine.rb
  end
end
