require 'thor'
require 'autoproj'
require 'rock/cli/release_admin'

module Rock
    module CLI
        # Management of releases from the point of view of the user
        #
        # The Rock scheme here is to store all release info in the common buildconf
        # repository. Each release has its own tag, and within the commit pointed-to
        # by the tag the files overrides.d/80-release.* contain the necessary
        # information:
        #    overrides.d/80-release.md: release notes (in markdown format)
        #    overrides.d/80-release.package_sets.yml: version information for the package sets
        #    overrides.d/80-release.packages.yml: version information for the packages
        #
        class Release < Thor
            # VCS information where the Rock release information is stored
            ROCK_RELEASE_INFO = Hash[
                'github' => 'rock-core/buildconf',
                'branch' => 'releases']

            RELEASE_NOTES    = "RELEASE_NOTES.md"
            RELEASE_VERSIONS = "overrides.d/25-release.yml"

            attr_reader :config
            attr_reader :config_dir
            attr_reader :package
            attr_reader :importer

            class InvalidReleaseName < Autobuild::PackageException; end

            def initialize(*args)
                super

                Autoproj.load_config
                Autoproj.silent do
                    require 'autoproj/gitorious'
                end
                Autoproj::CmdLine.initialize_root_directory
                @config_dir = Autoproj.config_dir
                vcs = Autoproj::VCSDefinition.from_raw(ROCK_RELEASE_INFO)
                @package = Autoproj::Ops::Tools.
                    create_autobuild_package(vcs, "main configuration", Autoproj.config_dir)
                @importer = package.importer
                importer.remote_name = 'rock-core'
            end

            no_commands do
                def fetch_release_notes(release_name)
                    verify_release_name(release_name)
                    importer.show(package, release_name, RELEASE_NOTES)
                end

                def fetch_version_file(release_name)
                    verify_release_name(release_name)
                    importer.show(package, release_name, RELEASE_VERSIONS)
                end
            
                def ensure_overrides_dir_present
                    FileUtils.mkdir_p Autoproj.overrides_dir
                end

                def verify_release_name(release_name, options = Hash.new)
                    Kernel.validate_options options,
                        only_local: false

                    importer.rev_parse(package, release_name)
                    importer.show(package, release_name, RELEASE_NOTES)
                rescue Autobuild::PackageException
                    if !options[:only_local]
                        # Try harder, fetch the remote branch
                        importer.fetch_remote(package)
                        return verify_release_name(release_name, only_local: true)
                    end
                    raise InvalidReleaseName.new(package, 'import'),
                        "#{release_name} does not look like a valid release name"
                end

                def match_names_to_packages_in_versions(names, versions, options = Hash.new)
                    names = names.flat_map do |name|
                        name = patter_matcher_from_arg(name)
                        entries = versions.find_all do |vcs|
                            key = vcs.keys.first
                            if key =~ /^pkg_set:/
                                (name === vcs['name']) || (name === key)
                            else
                                name === key
                            end
                        end

                        if entries.empty? && !options[:ignore_missing]
                            Autoproj.error "cannot find a package or package set matching #{name} in release #{release}"
                            return
                        end

                        entries
                    end

                    pkg_sets, pkgs = names.partition { |vcs| vcs.keys.first =~ /^pkg_set:/ }
                    if !pkg_sets.empty?
                        Autoproj.initialize_and_load
                        pkg_sets.each do |pkg_set_name|
                            pkg_set = Autoproj.manifest.package_set(pkg_set_name)
                            pkgs.concat(pkg_set.each_package.to_a)
                        end
                    end
                    pkgs
                end
            end

            default_command
            desc "list",
                "displays the list of known releases"
            option 'local', type: :boolean
            def list
                if !options[:local]
                    importer.fetch_remote(package)
                end

                tags = importer.run_git_bare(package, 'tag')
                releases = tags.find_all do |tag_name|
                    begin verify_release_name(tag_name, only_local: true)
                    rescue InvalidReleaseName
                    end
                end
                puts releases.sort.join("\n")
            end

            desc "versions RELEASE_NAME",
                "displays the version file of the given release"
            def versions(release_name)
                puts fetch_version_file(release_name)
            end

            desc "notes RELEASE_NAME",
                "displays the release notes for the given release"
            def notes(release_name)
                puts fetch_release_notes(release_name)
            end

            desc 'switch RELEASE_NAME', 'switch to a release, master or stable'
            def switch(release_name)
                if release_name == "master"
                    Autoproj.config.set("ROCK_SELECTED_FLAVOR", "master")
                    Autoproj.config.save
                    return
                elsif release_name == "stable"
                    Autoproj.config.set("ROCK_SELECTED_FLAVOR", "stable")
                    Autoproj.config.save
                    return
                end

                versions = fetch_version_file(release_name)
                ensure_overrides_dir_present
                File.open(File.join(config_dir, RELEASE_VERSIONS), 'w') do |io|
                    io.write versions
                end
                Autoproj.message "successfully setup release #{release_name}"
                Autoproj.message "  autoproj status will tell you what has changed"
                Autoproj.message "  aup --all will attempt to include the new release changes to your working copy"
                Autoproj.message "  aup --all --reset will (safely) reset your working copy to the release's state"
            end

            desc 'freeze-packages NAMES', 'freeze the given package(s) or package set. If a package set is given, its packages are frozen (but not the package set itself, use freeze-package-set for that)'
            def freeze_packages(*names)
                release_name = Autoproj.config.get('current_rock_release', false)
                if !release_name
                    Autoproj.error "currently not on any release, use rock-release switch first"
                    return
                end

                version_file = fetch_version_file(release_name)
                versions = YAML.load(version_file)

                pkgs = match_names_to_packages_in_versions(names, versions)

                to_merge = Hash.new
                pkgs.each do |pkg_name|
                    if ver = versions[pkg_name]
                        to_merge[pkg_name] = ver
                    end
                end

                ops = Autoproj::Ops::Snapshot.new(Autoproj.manifest)
                ops.save_versions(to_merge, File.join(config_dir, RELEASE_VERSIONS))
            end

            desc 'unfreeze-packages', 'Allow the given packages or package set to be updated.'
            def unfreeze
                release_name = Autoproj.config.get('current_rock_release', false)
                if !release_name
                    Autoproj.error "currently not on any release, use rock-release switch first"
                    return
                end

                release_versions_path = File.join(config_dir, RELEASE_VERSIONS)
                if !File.file?(release_versions_path)
                    Autoproj.error "#{release_versions_path} not present on disk, use autoproj switch to restore it first"
                    return
                end

                versions = YAML.load(File.read(release_versions_path))
                pkgs = match_names_to_packages_in_versions(names, versions, ignore_missing: true)

                versions.delete_if do |vcs|
                    pkgs.include?(vcs.keys.first)
                end

                ops = Autoproj::Ops::Snapshot.new(Autoproj.manifest)
                ops.save_versions(to_merge, release_versions_path, replace: true)
                Autoproj.message "updated #{release_versions_path}"
            end

            desc "admin", "commands to create releases"
            subcommand "admin", ReleaseAdmin
        end
    end
end

