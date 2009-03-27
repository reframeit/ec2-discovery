require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'
require 'ec2-discovery/messages/availability_message'

module ReframeIt
  module EC2
    ##
    # This processor keeps track of service availabilities
    ##
    class AvailabilityProcessor < MessageProcessor
      def initialize()
        super(AvailabilityMessage)

        # hash of service name => Array<available ipv4 addresses>
        @available = {}
        
        # hash of service name => Hash<ipv4 address => expiration time>
        @expires = {}
      end

      def process_impl(msg)
        if msg.available
          msg.services.each do |service|
            @available[service] ||= []
            @available[service] << msg.ipv4addr if !@available[service].include?(msg.ipv4addr)
            @expires[service] ||= {}
            @expires[service][msg.ipv4addr] = Time.now + msg.ttl
          end
        else
          msg.services.each do |service|
            @available[service].delete(msg.ipv4addr) if @available[service]
            @expires[service].delete(msg.ipv4addr) if @expires[service]
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
      # Returns: hash of ipv4 addresse => array<service names>  (or array<host names>)
      ##
      def all_ipv4addrs(to_hostnames = false)
        expired

        ips = {}
        @available.each do |service, ip_list|
          ip_list.each_with_index do |ip, idx|
            if to_hostnames
              idx_str = (idx+1).to_s

              if idx_str.length < 2
                idx_str = "0#{idx_str}"
              elsif idx_str.length > 2
                error "#{service} has #{ip_list.length} ip addresses. Limit is 99!"
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

      ##
      # get a list of expired services. Also removes these services from
      # our list of available services, since they're no longer needed.
      #
      # Returns: hash of <service name> => array<ipv4addr>
      ##
      def expired
        # service => ip_list
        to_delete = {}

        @expires.each do |service, ip_expire_list|
          ip_expire_list.each do |ip, expire|
            if expire < Time.now
              to_delete[service] ||= []
              to_delete[service] << ip
            end
          end
        end

        to_delete.each do |service, ip_list|
          ip_list.each do |ip|
            @available[service].delete(ip) if @available[service]
            @expires[service].delete(ip) if @expires[service]
          end
        end

        return to_delete
      end


    end
  end
end
