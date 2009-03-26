require 'logger'

module ReframeIt
  module EC2
    module Logger

      def Logger.logger
        if !@logger
          @logger = ::Logger.new(STDOUT)
          @logger.level = ::Logger::DEBUG
        end
        
        @logger
      end
      
      def Logger.logger=(logger)
        @logger = logger
      end

      def logger
        Logger.logger
      end

      def logger=(logger)
        Logger.logger=logger
      end

      def log(level, *msgs, &block)
        msgs.each{ |msg| logger.add(level, msg) }
        logger.add(level, nil, nil, &block) if block
      end
      alias :add :log

      def debug(*msgs, &block)
        log(::Logger::DEBUG, *msgs, &block)
      end
      def info(*msgs, &block)
        log(::Logger::INFO, *msgs, &block)
      end
      def warn(*msgs, &block)
        log(::Logger::WARN, *msgs, &block)
      end
      def error(*msgs, &block)
        log(::Logger::ERROR, *msgs, &block)
      end
      def fatal(*msgs, &block)
        log(::Logger::FATAL, *msgs, &block)
      end
    end
  end
end
