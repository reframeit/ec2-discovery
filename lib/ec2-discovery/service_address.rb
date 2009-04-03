module ReframeIt
  module EC2
    class ServiceAddress
      include Comparable

      # standard ipv4 address, as a string
      attr_accessor :ipv4

      # port specification starting with :
      # (e.g., :80 or :8000-8080)
      attr_accessor :port

      def initialize(ipv4, port='')
        @ipv4 = ipv4

        # make sure the port begins with a colon if a port is given
        if port
          port = port.strip
          if !port.empty? && !(port =~ /^:/)
            port = ":#{port}"
          end
        end

        @port = port
      end

      ##
      # override comparison to compare based on fields
      #
      # instead of dealing with nil tests and comparisons, we assume here
      # that if an address has a port string, that it is properly formed
      # (begins with ':'), and that ip addresses are properly formed, so we
      # can just combine them and compare the string, not having to worry about 
      # false positives
      ##
      def <=>(s)
        "#{@ipv4}#{@port}" <=> "#{s.ipv4}#{s.port}"
      end

      ##
      # override equality test
      ##
      def eql?(s)
        s.is_a?(ServiceAddress) && s == self
      end

      ##
      # override hash to maintain the property that a.eql?(b) ==> a.hash == b.hash
      ##
      def hash
        "#{@ipv4}#{@port}".hash
      end

    end
  end
end
