# frozen_string_literal: true

module SolidObserver
  module Paginatable
    extend ActiveSupport::Concern

    private

    def paginate_scope(scope, per_page:)
      @total_count = scope.count
      @total_pages = (@total_count.to_f / per_page).ceil
      @page = 1 if @page < 1
      @page = 1 if @page > @total_pages && @total_pages > 0
      (@page - 1) * per_page
    end
  end
end
