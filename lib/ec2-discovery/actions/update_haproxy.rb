require 'ec2-discovery/action'

module ReframeIt
  module EC2

    ##
    # This works by looking for listen and backend sections in /etc/haproxy.cfg 
    # that match the name of the services that are available.
    #
    # This updater will inject the available services as servers in the config file
    # and then reload haproxy, using the reload command.
    ## 
    class UpdateHAProxy < Action

      ##
      # Initialize a new updater.
      #
      # == Params:
      # +config_file+ - this is usuall /etc/haproxy.cfg, but since that requires
      #                 escalated privileges, it can be useful to change this
      #                 for testing
      # +extra_server_args+ - we can optionally append some args to the end of the server
      #                       declaration lines, like "check inter 1000"
      # +reload_cmd+ - the command we should use to reload haproxy (without stopping it)
      ##
      def initialize(config_file = "/etc/haproxy.cfg",
                     reload_cmd = "/etc/init.d/haproxy reload",
                     extra_server_args = "check inter 1000")
        @config_file = config_file
        @reload_cmd = reload_cmd
        @extra_server_args = extra_server_args
      end

      ## returns the lines of the file, as an array
      def read_config_file
        contents File.readlines(@config_file)

        # add a blank line at the end (sentinal)
        contents << "\n"
      end

      ## writes the given string to the config file
      def write_config_file(doc)
        File.open(@config_file, 'w') {|f| f.write(lines.join("\n"))}
      end

      ## reloads the latest haproxy config
      def reload_haproxy
        info "Reloading haproxy: '#{@reload_cmd}'"
        info `#{@reload_cmd}`
      end
      
      def invoke(availability_processor)
        debug { "updating haproxy..." }

        # service name => <list of [hostname, ip_address]>
        services = {}

        # get the services we need to know about, along with the hostnames and
        # ip addresses for them
        availability_processor.all_ipv4addrs(true).each do |ip_addr, hostnames|
          hostnames.each do |hostname|
            service = hostname[0..-3]
            services[service] ||= []
            services[service] << [hostname, ip_addr]
          end
        end
        
        marker_begin = "## BEGIN ec2-discovery ##"

        lines = []

        # read through the file, looking for any of the services we care about

        # indicates that we're currently in a service section that we care about
        processing_service = nil

        # when false, indicates that we're currently in a service section we care about, but
        # have not gotten to a point where we can inject our own lines.
        # when true, indicates that we've finished injecting our own lines, but there may
        # still be lines left to throw away (the ones we previously injected)
        done_replacing = false

        
        # if we come across data that was previously injected, we should delete it
        ignoring_old_data = false

        read_config_file.each do |line|
          # strip any newlines
          line = line.gsub("\n", '')
          line = line.gsub("\r", '')

          if processing_service
            if !done_replacing && ( (line =~ /^\s*#{marker_begin}/) || (line.strip.empty?) )
              # we got an empty line, or we got to a point where we started replacing last time
              lines << "#{marker_begin}"
              services[processing_service].each do |hostname, ip|
                lines << "  server #{hostname} #{ip} #{@extra_server_args}"
              end
              lines << ""
              
              # done replacing
              done_replacing = true

              # we might also be done with the service section
              processing_service = nil if line.strip.empty?
            elsif done_replacing
              if line.strip.empty?
                # we finished replacing, and are now done with the service
                processing_service = nil
              else
                # we finished replacing, but are not done with this service section, 
                # so ignore any more lines we see
              end
            else
              # still processing service, haven't gotten to where we can start
              # replacing lines
              lines << line
            end
          elsif line =~ /^\s*(listen|backend)/
            # chomp off the beginning
            service = line.gsub(/^\s*(listen|backend)\s*/, '')

            # chomp off anything after the service name
            service = service.gsub(/[^a-zA-Z0-9_-]+.*/, '')
            
            if services.has_key?(service)
              processing_service = service
              done_replacing = false
            else
              processing_service = nil
            end

            lines << line
          elsif line =~ (/^\s*#{marker_begin}/)
            # this must be an old marker from a previous time
            ignoring_old_data = true
          elsif ignoring_old_data && line.strip.empty?
            ignoring_old_data = false
            lines << line
          else # not in a section we care about
            lines << line unless ignoring_old_data
          end
        end

        lines << ""
        write_config_file(lines.join("\n"))
        reload_haproxy
        debug { "Updated haproxy" }    
      end
    end
  end
end
