require 'orocos'
require 'roby'
require 'utilrb/logger'
require 'pathname'

module Rock
    module Bundle
        extend Logger.Root("Bundle", Logger::INFO)

        def self.is_bundle_path?(path)
            File.file?(File.join(path, "config", "bundle.yml")) ||
                File.file?(File.join(path, "config", "app.yml"))
        end

        # Enumerates the path to every registered bundle, starting with the
        # one that has the highest priority
        def self.each_bundle
            if !block_given?
                return enum_for(:each_bundle)
            end

            paths = (ENV['ROCK_BUNDLE_PATH'] || '').split(":")
            if paths.empty?
                # Look for a bundle in the parents of Dir.pwd
                curdir = Pathname.new(Dir.pwd)
                while !curdir.root? && !is_bundle_path?(curdir.to_s)
                    curdir = curdir.parent
                end
                if !curdir.root?
                    paths << curdir.to_s
                end
            end
            paths.each do |path|
                if is_bundle_path?(path)
                    yield(path)
                else
                    Dir.new(path).each do |f|
                        f = File.join(path, f)
                        if is_bundle_path?(f)
                            yield(f)
                        end
                    end
                end
            end
        end

        # Returns the path to the current bundle
        def self.bundle_dir
            each_bundle.to_a.last
        end

        # Initializes the bundle support, and load all the available orocos info
        def self.load
            Bundle.info "initializing bundle support"
            if dir = bundle_dir
                Bundle.info "  main dir: #{dir}"
                Bundle.info "  search path:"
                each_bundle do |path|
                    Bundle.info "    #{path}"
                end
            else
                Bundle.info "  no bundle registered"
            end

            Roby.app.app_dir = bundle_dir
            Roby.app.search_path = each_bundle.to_a
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

Bundle = Rock::Bundle
