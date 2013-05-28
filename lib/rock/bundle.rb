require 'roby'
require 'utilrb/logger'
require 'utilrb/pathname/find_matching_parent'
require 'pathname'
require 'yaml'
require 'orocos'

module Rock
    # Bundle support
    #
    # In Rock, bundles are the packages in which system-related scripting,
    # modelling and tools are included. They are meant to "bind together" the
    # different components, packages and tool configuration from rock.
    #
    # In practice, the bundle implementation is a thin wrapper on top of the
    # rest of the rock 
    #
    # Bundle-aware scripts should simply use Bundle.initialize / Bundle.load
    # instead of Orocos.initialize / Orocos.load. This is in principle enough to
    # get bundle integration. All the rock-* tools on which bundle integration
    # makes sense should do that already.
    module Bundles
        extend Logger.Root("Bundles", Logger::INFO)

        # Representation of a bundle we found
        #
        # The bundle's configuration parameters are stored under the 'bundle'
        # key in either config/app.yml or config/bundle.yml
        #
        # config/app.yml or config/bundle.yml are used to recognize bundles from
        # normal directories. See Bundles.is_bundle_path?.
        class Bundle
            # The bundle name
            attr_reader :name
            # The full path to the bundle
            attr_reader :path
            # The bundle's configuration hash. It gets loaded ony if
            # #load_config is called.
            #
            # Configuration in bundles
            attr_reader :config
            # Returns true if this bundle can be found through the
            # ROCK_BUNDLE_PATH or if it must be referred to through its full
            # path
            def registered?
                paths = (ENV['ROCK_BUNDLE_PATH'] || '').split(":")
                paths.any? do |p|
                    p == path || path =~ /^#{Regexp.quote(p)}/
                end
            end

            def initialize(path)
                @name = File.basename(path)
                @path = path
            end

            # Loads the configuration file, or return an already loaded
            # configuration
            def load_config
                if @config
                    return config
                end

                if File.file?(bundle_yml = File.join(path, "config", "bundle.yml"))
                    base = YAML.load(File.read(bundle_yml))
                elsif File.file?(app_yml = File.join(path, "config", "app.yml"))
                    base = YAML.load(File.read(app_yml))
                end
                base ||= Hash.new
                @config = (base['bundle'] || Hash.new)
                @config['dependencies'] ||= Array.new
                config
            end

            # Enumerate the names of the bundles on which this bundle depends
            def each_dependency(&block)
                load_config['dependencies'].each(&block)
            end
        end

        # Returns true if +path+ is the root of a bundle
        def self.is_bundle_path?(path)
            File.file?(File.join(path, "config", "bundle.yml")) ||
                File.file?(File.join(path, "config", "app.yml"))
        end

        # Find the bundle in which we are currently, if there is one
        #
        # Returns nil if we are outside any bundle
        def self.find_bundle_from_current_dir
            find_bundle_from_dir(Dir.pwd)
        end

        # Selects the current bundle, regardless of the global configuration
        #
        # Raises ArgumentError if the current directory is not a bundle, or is
        # not contained in one
        #
        # This is meant to be mostly used in test scripts
        def self.select_current
            select(Dir.pwd)
        end
        
        # Select the bundle pointed-to by +directory+, or the bundle that
        # contains directory
        #
        # Raises ArgumentError if +directory+ is not part of a bundle
        def self.select(directory)
            if current_bundle = find_bundle_from_dir(Dir.pwd)
                ENV['ROCK_BUNDLE'] = current_bundle.path
            else
                raise ArgumentError, "#{directory} is not contained in a bundle"
            end
        end

        # Find the bundle that contains the provided directory
        #
        # Returns nil if there is none
        def self.find_bundle_from_dir(dir)
            # Look for a bundle in the parents of Dir.pwd
            bundle_dir = Pathname.new(dir).
                find_matching_parent { |curdir| is_bundle_path?(curdir.to_s) }
            if bundle_dir
                return Bundle.new(bundle_dir.to_s)
            end
        end

        # Enumerates the path to every registered bundle, starting with the
        # one that has the highest priority
        #
        # A directory is considered to be a bundle if it has a config/app.yml or
        # config/bundle.yml file (even an empty one)
        #
        # The bundles are enumerated following the ROCK_BUNDLE_PATH environment
        # variable:
        #
        # * if a directory in ROCK_BUNDLE_PATH is pointing to a bundle, it gets
        #   added
        # * if a directory in ROCK_BUNDLE_PATH is a directory that contains
        #   bundles, all the included bundles are added in an unspecified order
        #
        def self.each_bundle
            if !block_given?
                return enum_for(:each_bundle)
            end

            paths = (ENV['ROCK_BUNDLE_PATH'] || '').split(":")
            if paths.empty?
                if from_pwd = find_bundle_from_current_dir
                    paths << from_pwd.path
                end
            end

            current_bundle = ENV['ROCK_BUNDLE']
            if current_bundle && current_bundle.empty?
                current_bundle = nil
            end
            if current_bundle && Bundles.is_bundle_path?(current_bundle)
                yield(Bundle.new(File.expand_path(current_bundle)))
            end

            paths.each do |path|
                if !File.directory?(path)
                elsif is_bundle_path?(path)
                    yield(Bundle.new(path))
                else
                    Dir.new(path).each do |f|
                        f = File.join(path, f)
                        if is_bundle_path?(f)
                            yield(Bundle.new(f))
                        end
                    end
                end
            end
        end

        # Exception raised when it is expected that a bundle is present, but
        # none was found.
        class NoBundle < RuntimeError; end

        # Exception raised when the bundle support looks for a particular bundle
        # but cound not find it, such as during dependency resolution
        class BundleNotFound < RuntimeError
            # The name of the bundle that was being looked for
            attr_reader :name

            def initialize(name)
                @name = name
            end
        end

        # Returns the Bundle object that represents the current bundle (i.e. the
        # bundle in which we shoul be working).
        #
        # The current bundle can be defined, in order of priority, by:
        #
        # * the ROCK_BUNDLE environment variable, which should hold the name of
        #   the currently selected bundle
        # * the current directory
        # * if there is only one bundle found on this system, this bundle is
        #   returned
        def self.current_bundle
            all_bundles = each_bundle.to_a
            if bundle_name = ENV['ROCK_BUNDLE']
                bundle_path = File.expand_path(bundle_name)
                if bdl = all_bundles.find { |bdl| bdl.name == bundle_name || bdl.path == bundle_path }
                    return bdl
                else
                    raise ArgumentError, "cannot find currently selected bundle #{bundle_name} (available bundles are: #{all_bundles.map(&:name).sort.join(", ")})"
                end
            elsif current = find_bundle_from_current_dir
                return current
            elsif all_bundles.size == 1
                return all_bundles.first
            else
                raise NoBundle, "no bundle found"
            end
        end

        # Returns true if we have a selected bundle
        def self.has_selected_bundle?
            current_bundle
            true
        rescue NoBundle
            false
        end

        # Returns an array containing both +root_bundle+ and its dependencies
        # (recursively). The array is returned in order of priority.
        def self.discover_dependencies(root_bundle)
            all_bundles = self.each_bundle.to_a

            result = []
            queue = [root_bundle]
            while !queue.empty?
                root = queue.shift
                next if result.include?(root) || queue.include?(root)

                result << root
                root.each_dependency do |bundle_name|
                    bdl = all_bundles.find { |b| b.name == bundle_name }
                    if !bdl
                        raise BundleNotFound.new(bundle_name), "could not find bundle #{bundle_name}, listed as dependency in #{root.name} (#{root.path})"
                    end

                    queue << bdl
                end
            end
            result
        end

        def self.setup_search_paths(required = false)
            current_bundle =
                begin
                    self.current_bundle
                rescue NoBundle
                    if required
                        raise
                    end
                end

            if current_bundle
                selected_bundles = discover_dependencies(current_bundle)
                Bundles.info "Active bundles: #{selected_bundles.map(&:name).join(", ")}"
            else
                Bundles.info "No bundle currently selected"
                current_bundle = Bundle.new(Dir.pwd)
                selected_bundles = [current_bundle]
            end

            selected_bundles.reverse.each do |b|
                $LOAD_PATH.unshift(b.path) unless $LOAD_PATH.include?(b.path)
            end

            # Check if the current directory is in a bundle, and if it is the
            # case if that bundle is part of the selection. Otherwise, issue a
            # warning
            if current_dir = find_bundle_from_current_dir
                if !selected_bundles.any? { |b| b.path == current_dir.path }
                    sel = each_bundle.find { |b| b.path == current_dir.path }

                    Bundles.warn ""
                    Bundles.warn "The bundle that contains the current directory,"
                    Bundles.warn "  #{current_dir.name} (#{current_dir.path})"
                    Bundles.warn "is not currently active"
                    Bundles.warn ""
                    if sel
                        Bundles.warn "Did you mean to do bundles-sel #{sel.name} ?"
                    else
                        Bundles.warn "Did you mean to do bundles-sel #{current_dir.path} ?"
                    end
                end
            end

            Roby.app.app_dir = current_bundle.path
            Roby.app.load_config_yaml
            rock_bundle_path = (ENV['ROCK_BUNDLE_PATH'] || "").split(":")
            Roby.app.search_path = selected_bundles.map(&:path) + rock_bundle_path
            selected_bundles.reverse.each do |b|
                libdir = File.join(b.path, "lib")
                if File.directory?(libdir)
                    $LOAD_PATH.unshift libdir
                end
            end
        end

        # Initializes the bundle support, and load all the available orocos info
        def self.load(required = false)
            setup_search_paths

            require 'orocos'

            dir = Bundles.log_dir
            while !File.directory?(dir)
                Bundles.log_dir_created << dir
                dir = File.dirname(dir)
            end

            FileUtils.mkdir_p Bundles.log_dir
            Orocos.default_working_directory = Bundles.log_dir
            ENV['ORO_LOGFILE'] = File.join(Bundles.log_dir, "orocos.orocosrb-#{::Process.pid}.txt")

            # Load configuration directories
            find_dirs('models', 'orogen', :order => :specific_last, :all => true).each do |dir|
                Orocos.register_orogen_files(dir)
            end

            Orocos.load

            # Load configuration directories
            find_dirs('config', 'orogen', :order => :specific_last, :all => true).each do |dir|
                Orocos.conf.load_dir(dir)
            end

            # Check if the transformer is available. It if is, set it up
            begin
                require 'transformer/runtime'
                @transformer_config ||= "transforms.rb"
                if conf_file = find_file('config', @transformer_config, :order => :specific_first)
                    Transformer.use_bundle_loader
                    Orocos.transformer.load_conf(conf_file)
                end
            rescue LoadError
            end
        end

        def self.has_transformer?
            Orocos.respond_to?(:transformer)
        end

        def self.transformer_config=(file_name)
            # sets the name of the transformer file found in the config folder
            @transformer_config = file_name
        end

        def self.method_missing(m, *args, &block)
            if Orocos.respond_to?(m)
                Orocos.send(m, *args, &block)
            else
                super
            end
        end

        def self.run(*args, &block)
            # Process the given options to override some of the defaults
            options =
                if args.last.kind_of?(Hash)
                    args.pop
                else Hash.new
                end

            cmdline_options = [:gdb, :gdb_options, :valgrind, :valgrind_options, :wait]
            cmdline_wrappers, options = Kernel.filter_options options, cmdline_options
            cmdline_options.each do |key|
                if value = Scripts.send(key)
                    cmdline_wrappers[key] = value
                end
            end

            output_options, options = Kernel.filter_options options, :output => "%m-%p.txt"

            options = options.merge(cmdline_wrappers)
            options = options.merge(output_options)

            args.push(options)
            if has_transformer? && Transformer.broadcaster_name
                Orocos.transformer.start_broadcaster(Transformer.broadcaster_name, output_options) do
                    Orocos.run(*args, &block)
                end
            else
                Orocos.run(*args, &block)
            end
        end

        def self.is_ruby_script?(file)
            if file =~ /\.rb$/
                return true
            else
                first_line = File.open(file).each_line.find { true }
                return first_line =~ /^#!.*ruby/
            end
        end

        # Initializes the bundle support, and initializes the orocos layer
        def self.initialize
            # All logs are public by default in bundle scripts. This is overriden in rock-roby
            Roby.app.public_logs = Bundles.public_logs?

            if Orocos.initialized?
                raise ArgumentError, "Orocos.initialize has already been called. Do not call Orocos.initialize and Bundles.initialize multiple times"
            end

            self.load
            Roby.app.setup_dirs
            if Bundles.public_logs?
                Bundles.info "log files are going in #{Bundles.log_dir}"
            end
            Orocos.initialize
        end

        # Returns the task context referred to by +name+. Some common
        # configuration is done on this task, in particular the 'default'
        # configuration is applied if one is defined for the task's model
        def self.get(task_name)
            task = Orocos.name_service.get(task_name)
	    if !task.kind_of?(Orocos::Log::TaskContext)
                Orocos.conf.apply(task, ['default'])
	    end
            task
        end

        def self.parse_script_options(argv)
            parser = OptionParser.new do |opt|
                opt.on('--gdb[=TASKS]', String, 'run the comma-separated list of deployments using gdbserver. Do all if no arguments are given.') do |gdb|
                    Bundles::Scripts.gdb = gdb.split(',')
                end
                opt.on('--gdb-options=OPTIONS', String, 'comma-separated list of options that should be passed to the started gdbserver') do |gdb_options|
                    Bundles::Scripts.gdb_options = gdb_options.split(',')
                end
                opt.on('--gdb-port=PORT', Integer, 'base port that should be used for gdbserver') do |gdb_port|
                    Orocos::Process.gdb_base_port = gdb_port
                end
                opt.on('--valgrind[=TASKS]', String, 'run the comma-separated list of deployments using valgrind. Do all if no arguments are given.') do |valgrind|
                    Bundles::Scripts.valgrind = valgrind.split(',')
                end
                opt.on('--valgrind-options=OPTIONS', String, 'comma-separated list of options that should be passed to the started valgrind') do |valgrind_options|
                    Bundles::Scripts.valgrind_options = valgrind_options.split(',')
                end
                opt.on('--wait=SECONDS', Integer, 'wait that many seconds before deciding that a process will not start') do |wait|
                    Bundles::Scripts.wait = wait
                end
                opt.on("-h", "--help", "this help message") do
                    puts opt
                    exit 0
                end

                if block_given?
                    yield(opt)
                end
            end
            parser.parse(argv)
        end

        def self.change_default_options(args, defaults)
            args = args.dup
            if args.last.kind_of?(Hash)
                with_defaults, other = Kernel.filter_options args.pop, defaults
                args.push(with_defaults.merge(other))
            else
                args.push(defaults)
            end
            args
        end

        def self.find_dirs(*args)
            Roby.app.find_dirs(*args)
        end
        def self.find_dir(*args)
            args = change_default_options(args, :order => :specific_first)
            Roby.app.find_dir(*args)
        end
        def self.find_file(*args)
            args = change_default_options(args, :order => :specific_first)
            Roby.app.find_file(*args)
        end
        def self.find_files(*args)
            Roby.app.find_files(*args)
        end
        def self.find_files_in_dirs(*args)
            Roby.app.find_files_in_dirs(*args)
        end
        def self.log_dir
            Roby.app.log_dir
        end

        # If true, the logs are going to be kept. Otherwise, the log folder is
        # going to be deleted on shutdown
        def self.public_logs?
            @public_logs
        end

        def self.public_logs=(value)
            @public_logs = value
        end

        self.public_logs = true

        class << self
            attr_reader :log_dir_created
        end
        @log_dir_created = []

        module Scripts
            class << self
                attr_accessor :gdb
                attr_accessor :gdb_options
                attr_accessor :gdb_port
                attr_accessor :valgrind
                attr_accessor :valgrind_options
                attr_accessor :wait
            end
        end
    end
end

Bundles = Rock::Bundles

at_exit do
    created_dirs = Bundles.log_dir_created
    created_dirs.each do |dir|
        next if !File.directory?(dir)

        if Bundles.public_logs?
            contents = Dir.new(dir).to_a - %w{. ..}
            if contents.empty?
                Bundles.debug "removing empty log dir #{dir}"
                FileUtils.rmdir dir
            end
        else
            Bundles.debug "removing log dir #{dir} as public_logs? is false"
            FileUtils.rm_rf dir
        end
    end
end

