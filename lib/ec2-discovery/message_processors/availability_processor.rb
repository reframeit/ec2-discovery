require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'
require 'ec2-discovery/messages/availability_message'

module ReframeIt
  module EC2
    ##
    # This processor keeps track of service availabilities
    ##
    class AvailabilityProcessor < MessageProcessor
      def initialize
        super(AvailabilityMessage)

        # hash of service name => Array<available ipv4 addresses>
        @available = {}
      end

      def process_impl(msg)
        if msg.available
          msg.services.each do |service|
            @available[service] ||= []
            @available[service] << msg.ipv4addr if !@available[service].include?(msg.ipv4addr)
          end
        else
          msg.services.each do |service|
            @available[service].delete(msg.ipv4addr) if @available[service]
          end
        end
      end

      ##
      # gets the current list of available ipv4 addresses for the given service
      #
      # Returns: an array (possibly empty) of ipv4 addresses (as strings)
      ##
      def ipv4addrs(service)
        @available[service] || []
      end

      ##
      # gets all the available ipv4 addresses, along with the services at each address
      #
      # if the +to_hostnames+ flag is true, then the services will each have a 2-digit number
      # appended to them, starting at 01. If +to_hostnames+ is false (default), then the
      # same service name may appear multiple times.
      #
      # TODO: if to_hostnames is set, we currently have a limit of 99 ip addresses for
      # any given service. We do not currently check this condition.
      #
      # Returns: hash of ipv4 addresse => array<service names>  (or array<host names>)
      ##
      def all_ipv4addrs(to_hostnames = false)
        ips = {}
        @available.each do |service, ip_list|
          ip_list.each_with_index do |ip, idx|
            if to_hostnames
              idx_str = (idx+1).to_s

              if idx_str.length < 2
                idx_str = "0#{idx_str}"
              elsif idx_str.length > 2
                STDERR.puts "ERROR: #{service} has #{ip_list.length} ip addresses. Limit is 99!"
                next
              end

              service_str = "#{service}#{idx_str}"
            else
              service_str = service
            end
            
            ips[ip] ||= []
            ips[ip] << service_str
          end
        end

        return ips
      end


    end
  end
end
