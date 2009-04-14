require 'ec2-discovery/message_processor'
require 'ec2-discovery/message'
require 'ec2-discovery/messages/availability_message'
require 'ec2-discovery/service_address'

module ReframeIt
  module EC2
    ##
    # This processor keeps track of service availabilities
    ##
    class AvailabilityProcessor < MessageProcessor

      ##
      # a block that is passed this processor as a param and is
      # called when the availability list changes
      ##
      attr_accessor :availability_changed

      ##
      # Only the monitor should keep track of services expiring. That
      # way, the monitor can go down, and current services will maintain
      # their lists of who else is available.
      ##
      def initialize(keep_track_of_expires = false)
        super(AvailabilityMessage)

        @keep_track_of_expires = keep_track_of_expires

        # hash of service name => Array<ServiceAddress>
        @available = {}
        
        # hash of service name => Hash<ServiceAddress => expiration time>
        @expires = {} if @keep_track_of_expires

        # block called when our list changes
        @availability_changed = nil
      end

      ##
      # fire that the availability has change
      # this signals that the availability_changed block, if any, will be called,
      # but allows for multiple fires in close proximity to be grouped together
      #
      # +max_wait_time+ - number of seconds that we will wait, at most,
      #                   before firing off the availability_changed block
      ##
      def fire_availability_changed(max_wait_time = 3)
        if @availability_changed && !@availability_changed_thread
          outer = self
          @availability_changed_thread = Thread.new do
            sleep max_wait_time
            begin
              @availability_changed.call(outer)
            rescue Exception => ex
              error "Exception while executing availability_changed block!", ex
            end
            @availability_changed_thread = nil
          end
        end
      end

      def process_impl(msg)
        changed = false

        if msg.available
          msg.services.each do |service|
            port = service[/:.*$/] || ''
            service = service.gsub(/:.*$/, '')
            address = ServiceAddress.new(msg.ipv4addr, port)

            @available[service] ||= []
            if !@available[service].include?(address)
              @available[service] << address
              changed = true
              debug{ "Availability changed because #{service} at #{address.inspect} is available" }
            end
            if @keep_track_of_expires
              @expires[service] ||= {}
              @expires[service][address] = Time.now + 2*msg.ttl
              debug { "#{service} at #{address.inspect} will expire in #{msg.ttl} seconds (at #{@expires[service][address]})" }
            end
          end
        else # unavailability message
          msg.services.each do |service|
            port = service[/:.*$/] || ''
            service = service.gsub(/:.*$/, '')
            address = ServiceAddress.new(msg.ipv4addr, port)

            if @available[service]
              @available[service].delete(address)
              changed = true
              debug{ "Availability changed because #{service} at #{address.inspect} is unavailable" }
            end
            
            if @keep_track_of_expires
              @expires[service].delete(address) if @expires[service]
            end
          end
        end

        # let any listeners (eventually) know about the change in availability
        fire_availability_changed if changed
      end

      ##
      # gets the current list of available addresses for the given service
      #
      # Returns: an array (possibly empty) of ServiceAddress objects
      ##
      def available(service)
        @available[service] || []
      end

      ##
      # gets all the available addresses, along with the services at each address
      #
      # if the +to_hostnames+ flag is true, then the services will each have a 2-digit number
      # appended to them, starting at 01. If +to_hostnames+ is false (default), then the
      # same service name may appear multiple times.
      #
      # if the +include_ports+ flag is true, then the resulting service names (or hostnames)
      # will include the :port or :port1-port2 specifiers if they exist for that
      # service.
      #
      # Returns: hash of ipv4 address => array<service names>
      #          or ipv4 address => array<hostnames> if to_hostnames is true
      ##
      def all_available(to_hostnames = false, include_ports = false)
        addresses = {}
        @available.each do |service, addr_list|
          last_addr = nil
          idx = 0

          addr_list.each do |addr|
            if to_hostnames

              # keep the last index string if the ip is the same as the previous
              if !last_addr || addr.ipv4 != last_addr.ipv4
                idx += 1
              end
              idx_str = idx.to_s

              if idx_str.length < 2
                idx_str = "0#{idx_str}"
              elsif idx_str.length > 2
                error "#{service} has #{addr_list.length} addresses. Limit is 99!"
                next
              end
              
              last_addr = addr


              service_str = "#{service}#{idx_str}"
            else
              service_str = service
            end
            
            service_str = "#{service_str}#{addr.port}" if include_ports

            addresses[addr.ipv4] ||= []
            addresses[addr.ipv4] << service_str if !addresses[addr.ipv4].include?(service_str)
          end
        end

        return addresses
      end

      ##
      # get a list of expired services. Also removes these services from
      # our list of available services, since they're no longer needed.
      #
      # Returns: hash of <service name> => array<ServiceAddress>
      ##
      def expired
        # service => addr_list
        to_delete = {}

        @expires.each do |service, addr_expire_list|
          addr_expire_list.each do |addr, expire|
            if expire < Time.now
              to_delete[service] ||= []
              to_delete[service] << addr
            end
          end
        end

        to_delete.each do |service, addr_list|
          addr_list.each do |addr|
            @available[service].delete(addr) if @available[service]
            @expires[service].delete(addr) if @expires[service]
          end
        end
        
        debug{ "to_delete = #{to_delete.inspect}" }
        return to_delete
      end


    end
  end
end
