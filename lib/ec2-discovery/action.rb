module ReframeIt
  module EC2
    ##
    # An action is invoked every time the list of hosts 
    # that an instance is interested in changes.
    # 
    # This occurs when an availability message comes
    # in for a service it subscribes to on a new ip address (or a new availability).
    # For monitors, this occurs when 
    ##
    class Action
      include ReframeIt::EC2::Logger

      ##
      # a block that can perform the action
      # takes one param, an availability_processor
      ##
      attr_accessor :action_block

      ##
      # constructs a new action, optionally passing in the block that will be 
      # called when the host list updates.
      # 
      # == Params:
      # +action_block+ - the block that will be invoked as part of the action.
      # this block should take a single param, an AvailabilityProcessor
      ##
      def initialize(&action_block)
        @action_block = action_block if action_block
      end

      ##
      # Performs the action
      # 
      # == Params:
      # +availability_processor+ a ReframeIt::EC2::AvailabilityProcessor
      ##
      def invoke(availability_processor)
        @action_block.call(availability_processor)
      end
    end
  end
end
