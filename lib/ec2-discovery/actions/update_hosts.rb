require 'ec2-discovery/action'

module ReframeIt
  module EC2

    ##
    # This action updates our /etc/hosts file, using service names as host names
    # (where each service is appended with a 2-digit incrementing number to create the
    #  hostnames)
    ##
    class UpdateHosts < Action
      def initialize(local_ipv4 = '127.0.0.1', local_name = 'local_name', public_ipv4 = '0.0.0.0', public_name = 'public_name')
        @local_ipv4 = local_ipv4
        @local_name = local_name
        @public_ipv4 = public_ipv4
        @public_name = public_name
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
        all_ips = availability_processor.all_ipv4addrs(true)

        # add an alias for our local internal address
        all_ips[@local_ipv4] ||= []
        all_ips[@local_ipv4] << @local_name

        # add an alias for our external address
        all_ips[@public_ipv4] ||= []
        all_ips[@public_ipv4] << @public_name

        all_ips.each do |ip, service_list|
          lines << "#{ip} #{service_list.join(' ')}"
        end
        lines << "#{marker_end}\n"
        
        File.open("/etc/hosts", 'w') {|f| f.write(lines.join("\n"))}
        debug { "Updated hosts" }        
      end
    end
  end
end
