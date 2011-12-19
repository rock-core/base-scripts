require 'orocos'
require 'roby'
require 'utilrb/logger'
require 'pathname'

module Rock
    module Bundles
        extend Logger.Root("Bundles", Logger::INFO)

        class Bundle
            attr_reader :name
            attr_reader :path
            attr_reader :config

            def initialize(path)
                @name = File.basename(path)
                @path = path
            end

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
            # Look for a bundle in the parents of Dir.pwd
            curdir = Pathname.new(Dir.pwd)
            while !curdir.root? && !is_bundle_path?(curdir.to_s)
                curdir = curdir.parent
            end
            if !curdir.root?
                return Bundle.new(curdir.to_s)
            end
        end

        # Enumerates the path to every registered bundle, starting with the
        # one that has the highest priority
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

            paths.each do |path|
                if is_bundle_path?(path)
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

        class NoBundle < RuntimeError; end
        class BundleNotFound < RuntimeError
            # The name of the bundle that was being looked for
            attr_reader :name

            def initialize(name)
                @name = name
            end
        end

        def self.current_bundle
            all_bundles = each_bundle.to_a
            if bundle_name = ENV['ROCK_BUNDLE']
                if bdl = all_bundles.find { |bdl| bdl.name == bundle_name }
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

        # Initializes the bundle support, and load all the available orocos info
        def self.load(required = false)
            Bundles.info "initializing bundle support"
            current_bundle =
                begin
                    self.current_bundle
                rescue NoBundle
                    if required
                        raise
                    end
                end

            Bundles.info "  available bundles:"
            each_bundle do |b|
                Bundles.info "    #{b.name} (#{b.path})"
            end
            if current_bundle
                Bundles.info "  current_bundle: #{current_bundle.name} in #{current_bundle.path}"
            else
                Bundles.info "  no bundle registered"
                return
            end

            selected_bundles = discover_dependencies(current_bundle)
            selected_bundles.each do |b|
                $LOAD_PATH.unshift(current_bundle.path) unless $LOAD_PATH.include?(current_bundle.path)
            end
            Bundles.info "  selected bundles: #{selected_bundles.map(&:name).join(", ")}"

            Roby.app.app_dir = current_bundle.path
            Roby.app.search_path = selected_bundles.map(&:path)
            Orocos.load
        end

        # Initializes the bundle support, and initializes the orocos layer
        def self.initialize
            self.load
            Orocos.initialize
        end

        def self.find_dirs(*args)
            Roby.app.find_dirs(*args)
        end
        def self.find_files(*args)
            Roby.app.find_files(*args)
        end
        def self.find_files_in_dirs(*args)
            Roby.app.find_files_in_dirs(*args)
        end

        def self.run(*spec)
        end
    end
end

Bundles = Rock::Bundles
