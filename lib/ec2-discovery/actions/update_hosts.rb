require 'ec2-discovery/action'
require 'ec2-discovery/message_processors/availability_processor'
require 'ec2-discovery/service_address'

module ReframeIt
  module EC2

    ##
    # This action updates our /etc/hosts file, using service names as host names
    # (where each service is appended with a 2-digit incrementing number to create the
    #  hostnames)
    #
    # +update_immediately+ - if true, we right to the hosts file as soon as we are
    #                        initialized, in order to write any local settings
    ##
    class UpdateHosts < Action

      # set to true for testing, false otherwise
      attr_accessor :pretend
      
      # when testing, this is what we would have last written
      attr_accessor :pretend_output

      def initialize(local_ipv4 = '127.0.0.1', local_name = 'local_name', public_ipv4 = '0.0.0.0', public_name = 'public_name', update_immediately = true)
        @local_ipv4 = local_ipv4
        @local_name = local_name
        @public_ipv4 = public_ipv4
        @public_name = public_name

        @pretend = false

        # we should update our hosts right away, so we can get any 
        # local settings in there at least
        self.invoke(AvailabilityProcessor.new) if update_immediately
      end

      def invoke(availability_processor)
        debug { "updating hosts..." }
        
        marker_begin = "## BEGIN ec2-discovery ##"
        marker_end = "## END ec2-discovery ##"

        lines = []

        # read the file, stripping out a discovery section if we find one
        stripping = false
        File.readlines("/etc/hosts").each do |line|
          if !stripping && line =~ /^\s*#{marker_begin}/
              stripping = true
          elsif stripping && line =~ /^\s*#{marker_end}/
              stripping = false
          else
            # TODO: what if one of these ip addresses gets reused later?
            # for now, just ignoring them
            lines << line.strip if !stripping
          end
        end

        lines << "#{marker_begin}"
        # add the currently available ip addresses and services
        all_ips = availability_processor.all_available(true, false)

        # add an alias for our local internal address
        all_ips[@local_ipv4] ||= []
        if @local_name.is_a?(Array)
          all_ips[@local_ipv4] |= @local_name
        else
          all_ips[@local_ipv4] << @local_name
        end

        # add an alias for our external address
        all_ips[@public_ipv4] ||= []
        if @public_name.is_a?(Array)
          all_ips[@public_ipv4] |= @public_name
        else
          all_ips[@public_ipv4] << @public_name
        end

        all_ips.each do |ip, service_list|
          lines << "#{ip} #{service_list.join(' ')}"
        end
        lines << "#{marker_end}\n"

        if @pretend
          info "In pretend mode, so not writing /etc/hosts"
          debug { "I would have written:\n#{lines.join("\n")}" }
          @pretend_output = lines.join("\n")
        else
          File.open("/etc/hosts", 'w') {|f| f.write(lines.join("\n"))}
        end
        debug { "Updated hosts" }        
      end
    end
  end
end
