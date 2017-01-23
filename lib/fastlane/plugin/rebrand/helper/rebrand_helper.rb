module Fastlane
  module Helper
    class RebrandHelper
      # class methods that you define here become available in your action
      # as `Helper::RebrandHelper.your_method`
      #
      def self.show_message
        UI.message("Hello from the rebrand plugin helper!")
      end
    end
  end
end
