#!/usr/bin/env ruby

require 'json'
require 'logger'
require 'optparse'
require 'io/console'

require 'rbvmomi'

module DumpVcenterFolders
  VERSION = '0.0.1'.freeze

  class CLI
    def initialize(argv = [])
      @options = {user: ENV['VCENTER_USER'],
                  password: ENV['VCENTER_PASSWORD'],
                  server: ENV['VCENTER_SERVER']}
      @logger = Logger.new($stderr)
      @logger.level = Logger::INFO
      @logger.formatter = Logger::Formatter.new
      @logger.formatter.datetime_format = "%Y-%m-%dT%H:%M:%S.%3N%:z "

      @optparser = OptionParser.new do |parser|
        parser.banner = <<-EOS
Usage: dump-vcenter-folders [options] [folder_name] [...]

Connect to a vCenter server and recursively dump the structure for one or more
VM Folders in a datacenter as JSON. If no specific folders are listed in ARGV,
then all folders in the datacenter will be scanned.
EOS
        parser.separator("\nOptions:")

        parser.on('-d', '--datacenter DATACENTER', String,
                  'Datacenter to copy folder info from.') {|v| @options[:datacenter] = v }

        parser.on('-u', '--user USERNAME', String,
                  'User account to use when connecting with vCenter.',
                  'Defaults to the value of the VCENTER_USER env variable.') {|v| @options[:user] = v }

        parser.on('-p', '--password PASSWORD', String,
                  'Password to use when connecting with vCenter.',
                  'Defaults to the value of the VCENTER_PASSWORD env variable.',
                  'Will be read securely from STDIN if unset.') {|v| @options[:user] = v }

        parser.on('-s', '--server SERVER_HOSTNAME', String,
                  'Hostname of the vCenter server.',
                  'Defaults to the value of the VCENTER_SERVER env variable.') {|v| @options[:server] = v }


        parser.on_tail('-h', '--help', 'Show help') do
          $stdout.puts(parser.help)
          exit 0
        end

        parser.on_tail('--version', 'Show version') do
          $stdout.puts(VERSION)
          exit 0
        end
      end

      args = argv.dup
      @optparser.parse!(args)

      [:user, :server].each do |v|
        if @options[v].nil?
          raise ArgumentError, "A value for #{v} must be provided by the --#{v} flag or VCENTER_#{v.to_s.upcase} environment variable."
        end
      end

      # TODO: Maybe provide an option for reading the password from a file?
      if @options[:password].nil?
        $stderr.write "Enter vCenter password for #{@options[:user]}: "
        @options[:password] = $stdin.noecho(&:gets).chomp
      end

      @options[:folders_to_copy] = args # parse! consumes all flags
    end

    def run
      @logger.info("Connecting to #{@options[:server]}...")
      vcenter = RbVmomi::VIM.connect(host: @options[:server],
                                     user: @options[:user],
                                     password: @options[:password],
                                     insecure: true)

      if @options[:datacenter].nil?
        dcs = vcenter.rootFolder.children.select{|c| c.is_a?(RbVmomi::VIM::Datacenter)}
        $stderr.write("Available datacenters:\n\n\t")
        $stderr.puts(dcs.map(&:name).join("\n\t"))

        raise ArgumentError, 'A datacenter must be selected with the --datacenter flag'
      end


      dc = vcenter.serviceInstance.find_datacenter(@options[:datacenter])
      raise ArgumentError, "Could not find the specified datacenter: #{@options[:datacenter]}" if dc.nil?

      @logger.info("Reading directory structure from #{@options[:datacenter]}...")

      dirs_to_copy = if @options[:folders_to_copy].empty?
                       dc.vmFolder.children.select {|c| c.is_a?(RbVmomi::VIM::Folder)}.map(&:name)
                     else
                       @options[:folders_to_copy]
                     end

      dir_map = {}
      dir_map.default_proc = proc do |hash, key|
        hash[key] = []
      end

      dir_mapper = lambda do |path, dir_map, datacenter|
        @logger.info("Processing folder: #{path}")

        dir = datacenter.find_folder(path)

        dir.children.each do |child|
          case child
          when RbVmomi::VIM::VirtualMachine
            dir_map[path] << {name: child.name,
                              uuid: child.config.uuid}
          when RbVmomi::VIM::Folder
            dir_mapper.call([path, child.name].join('/'),
                            dir_map,
                            datacenter)
          else
            @logger.warn("Unknown entry of type #{child.class} in #{path}")
            next
          end
        end
      end

      dirs_to_copy.each do |dirname|
        dir_mapper.call(dirname, dir_map, dc)
      end

      @logger.info('Printing directory structure to STDOUT as JSON')
      $stdout.write(JSON.pretty_generate(dir_map))
    end
  end
end


# CLI Entrypoint
if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  begin
    DumpVcenterFolders::CLI.new(ARGV).run
  rescue => e
    $stderr.puts("ERROR #{e.class}: #{e.message}")
    exit 1
  end
end