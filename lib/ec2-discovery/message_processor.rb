module ReframeIt
  module EC2
    ##
    # A MessageProcessor is responsible for handling a specific 
    # class of messages, and will also be passed any subclass of
    # that type of message as well.
    #
    # Subclasses of this class should override +process_impl+, but
    # leave +process+ as is.
    ##
    class MessageProcessor

      ##
      # The subclass of ReframeIt::EC2::Message that this processor
      # handles. This must be a class object, not a string.
      ##
      attr_accessor :msg_clazz

      ##
      # This callback will be called just before a message is
      # processed. It may be useful to do some filtering on the
      # message.
      # This should be a block that takes as input a ReframeIt::EC2::Message
      # (of the specified type), and returns true if that message should
      # be processed by this processor.
      ##
      attr_accessor :pre_process

      ##
      # This is similar to the +pre_process+ callback, except it is called
      # after successful processing of the message. Its return type is void.
      ##
      attr_accessor :post_process

      ##
      # Creates a new processor for the given class of messages.
      #
      # You may pass a block into this constructor, which will be used 
      # to process the messages. Alternatively, you can subclass this class
      # and override process.
      ##
      def initialize(msg_clazz, &block)
        @msg_clazz = msg_clazz
        @block = block
      end

      ##
      # processes the given message, which is guaranteed
      # to be either a +msg_clazz+ object, or an instance of 
      # a subclass of +msg_clazz+.
      #
      # If this method raises an exception, then the message will
      # not be removed from the queue, so be careful with error
      # handling so as to avoid queue bloat.
      ##
      def process(msg)
        if @pre_process && !@pre_process.call(msg)
          return
        end

        process_impl(msg)

        @post_process.call(msg) if @post_process
      end


      protected

      ##
      # This is where the processing actually occurs, and is the
      # method that should be overridden in subclasses
      ##
      def process_impl(msg)
        if @block
          @block.call(msg)
        else
          STDERR.puts "WARNING: no block was passed in to this processor!"
        end
      end
    end
  end
end
