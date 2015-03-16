require 'thor'
require 'autoproj'

module Rock
    module CLI
        class Release < Thor
            # Implementation of the rock-release admin subcommand
            class Admin < Thor
                class_option :verbose, type: :boolean, default: false
                def self.exit_on_failure?; true end

                attr_reader :config_dir

                ROCK_VCS_LOCATIONS = [
                    /gitorious.*\/rock(?:-\w+)?\//,
                    /github.*\/rock(?:-\w+)?\//,
                    /github.*\/orocos-toolchain\//]

                def initialize(*args)
                    super
                    Autoproj.load_config
                    Autoproj::CmdLine.initialize_root_directory
                    @config_dir = Autoproj.config_dir
                end

                no_commands do
                    def invoke_command(*args, &block)
                        super
                    rescue Exception => e
                        Autoproj.error e.message
                        if options[:verbose]
                            e.backtrace.each do |bt|
                                Autoproj.error "  #{bt}"
                            end
                        end
                        exit 1
                    end

                    # Returns all packages that are necessary within the created
                    # release
                    def all_necessary_packages(manifest)
                        manifest.each_package_definition.find_all do |pkg|
                            Rock.flavors.package_in_flavor?(pkg.name, 'stable')
                        end
                    end

                    def ensure_autoproj_initialized
                        if !Autoproj.manifest
                            Autoproj.silent do
                                Autoproj::CmdLine.initialize_and_load([])
                            end
                        end
                        Autoproj.manifest
                    end

                    def rock_package?(package)
                        ROCK_VCS_LOCATIONS.any? { |matcher| matcher === package.vcs.url }
                    end

                    def tag_rock_packages(packages, release_name, options = Hash.new)
                        options = Kernel.validate_options options,
                            branch: 'stable'
                        branch = options[:branch]
                        packages.find_all do |pkg|
                            importer = pkg.importer

                            # Make sure that there is a stable branch, and that
                            # HEAD is in it
                            if (current_branch = importer.current_branch(pkg)) != "refs/heads/#{branch}"
                                pkg.error("%s is currently not on branch #{branch} (#{current_branch})")
                                true
                            elsif !importer.commit_present_in?(pkg, branch, 'HEAD')
                                pkg.error("%s's current HEAD is not included in its #{options[:branch]} branch")
                                true
                            else
                                begin
                                    importer.run_git_bare(pkg, 'tag', '-f', release_name)
                                    false
                                rescue Exception => e
                                    pkg.error e.message
                                    true
                                end
                            end
                        end
                    end

                    def package_changelog(pkg, from_tag, to_tag)
                        pkg_name =
                            if pkg.respond_to?(:text_name)
                                pkg.text_name
                            else pkg.autoproj_name
                            end

                        result = [pkg_name, [], []]

                        if !pkg.importer.respond_to?(:status)
                            return
                        end


                        status = pkg.importer.delta_between_tags(pkg, from_tag, to_tag)
                        if status.uncommitted_code
                            Autoproj.warn "the #{pkg_name} package contains uncommitted modifications"
                        end

                        case status.status
                        when Autobuild::Importer::Status::UP_TO_DATE
                            result[0] = "#{pkg_name}: in sync"
                        else
                            result[1] = status.local_commits
                            result[2] = status.remote_commits
                        end

                        result
                    end
                end

                desc 'validate-maintainers', "checks that all packages have a maintainer"
                def validate_maintainers
                    manifest = ensure_autoproj_initialized
                    packages = all_necessary_packages(manifest)
                    packages.each do |pkg|
                        pkg = pkg.autobuild
                        if !File.directory?(pkg.srcdir)
                            Autoproj.warn "#{pkg.srcdir} not present on disk"
                        else
                            pkg_manifest = manifest.load_package_manifest(pkg.name)
                            maintainers = pkg_manifest.each_maintainer.to_a
                            if maintainers.empty?
                                authors = pkg_manifest.each_author.to_a
                                if authors.empty?
                                    pkg.error("%s has no maintainer and no author")
                                else
                                    pkg.warn("%s has no maintainer but has #{authors.size} authors: #{authors.sort.join(", ")}")
                                end
                            else
                                pkg.message("%s has #{maintainers.size} declared maintainers: #{maintainers.sort.join(", ")}")
                            end
                        end
                    end
                end

                desc "create-rc", "create a release candidate environment"
                option :branch, doc: "the release candidate branch", type: :string, default: 'rock-rc'
                option :exclude, doc: "packages on which the RC branch should not be created", type: :array, default: []
                option :notes, doc: "whether it should generate release notes", type: :boolean, default: true
                option :update, type: :boolean, default: true, doc: "whether the RC branch should be updated even if it exists or not"
                def create_rc
                    manifest = ensure_autoproj_initialized
                    packages = all_necessary_packages(manifest)

                    Autoproj.message "Checking out missing packages"
                    missing_packages = packages.find_all { |pkg| !File.directory?(pkg.autobuild.srcdir) }
                    missing_packages.each_with_index do |pkg, i|
                        Autoproj.message "  [#{i + 1}/#{missing_packages.size}] #{pkg.name}"
                        pkg.autobuild.import(checkout_only: true)
                    end

                    excluded_by_user = options[:exclude].flat_map do |entry|
                        entry.split(',')
                    end

                    branch = options[:branch]
                    versions = Array.new

                    Autoproj.message "Creating the package sets RC branch"
                    package_sets = manifest.each_remote_package_set.to_a
                    package_sets.each_with_index do |pkg_set, i|
                        Autoproj.message "  [#{i}/#{package_sets.size}] #{pkg_set.repository_id}"
                        pkg = pkg_set.create_autobuild_package
                        if options[:update] || !pkg.importer.has_commit?(pkg, "refs/remotes/autobuild/#{branch}")
                            pkg.importer.run_git_bare(pkg, 'remote', 'update')
                            pkg.importer.run_git_bare(pkg, 'push', 'autobuild', "+refs/remotes/autobuild/master:refs/heads/#{branch}")
                        end
                        versions << Hash["pkg_set:#{pkg_set.repository_id}" => Hash['branch' => branch]]
                    end

                    Autoproj.message "Creating the packages RC branch"
                    # Deal with the packages that are managed within Rock
                    packages_to_branch_out, packages_to_snapshot = packages.partition do |pkg|
                        !excluded_by_user.include?(pkg.name) && rock_package?(pkg)
                    end
                    packages_to_branch_out.each_with_index do |pkg, i|
                        Autoproj.message "  [#{i + 1}/#{packages_to_branch_out.size}] #{pkg.name}"
                        pkg = pkg.autobuild
                        if options[:update] || !pkg.importer.has_commit?(pkg, "refs/remotes/autobuild/#{branch}")
                            pkg.importer.run_git_bare(pkg, 'remote', 'update')
                            pkg.importer.run_git_bare(pkg, 'push', 'autobuild', "+refs/remotes/autobuild/stable:refs/heads/#{branch}")
                        end
                        versions << Hash[pkg.name => Hash['branch' => branch]]
                    end
                    ops = Autoproj::Ops::Snapshot.new(manifest)
                    versions += ops.snapshot_packages(packages_to_snapshot.map { |pkg| pkg.autobuild.name })

                    vcs = Autoproj::VCSDefinition.from_raw(ROCK_RELEASE_INFO)
                    buildconf = Autoproj::Ops::Tools.
                        create_autobuild_package(vcs, "main configuration", config_dir)
                    version_commit = Autoproj::Ops::Snapshot.create_commit(buildconf, Release::RELEASE_VERSIONS, "version file for tracking the release candidate") do |io|
                        YAML.dump(versions, io)
                    end
                    notes_commit = Autoproj::Ops::Snapshot.create_commit(buildconf, Release::RELEASE_NOTES, "release notes file to please rock-release", version_commit) do |io|
                        io.puts "This is an empty file meant to allow rock-release to see rock-rc as a release"
                    end
                    buildconf.importer.run_git_bare(buildconf, 'tag', '-f', 'rock-rc', notes_commit)
                    buildconf.importer.run_git_bare(buildconf, 'push', '-f', '--tags', buildconf.importer.push_to)
                end

                desc "checkout", "checkout all packages that are included in 'stable'. This is done by 'prepare'"
                def checkout
                    manifest = ensure_autoproj_initialized
                    all_necessary_packages(manifest).each do |pkg|
                        pkg.autobuild.import(checkout_only: true)
                    end
                end

                desc "notes RELEASE_NAME LAST_RELEASE_NAME", "create a release notes file based on the package's changelogs"
                def release_notes(release_name, last_release_name)
                    manifest = ensure_autoproj_initialized
                    packages = all_necessary_packages(manifest)

                    ops = Release.new
                    last_versions_file = ops.fetch_version_file(last_release_name)
                    last_versions = YAML.load(last_versions_file)

                    last_packages_names = last_versions.map { |vcs| vcs.keys.first }.
                        find_all { |name| name !~ /^pkg_set:/ }

                    packages_names = packages.map { |pkg| pkg.autobuild.name }
                    new_packages     = package_names - last_packages_names
                    obsolete_packages = last_packages_names - packages_names

                    errors = Array.new
                    status = Array.new
                    packages.each do |pkg|
                        pkg_name = pkg.autobuild.name
                        next if new_packages.include?(pkg_name)
                        next if obsolete_packages.include?(pkg_name)

                        changes = package_changelog(pkg.autobuild, release_name, last_release_name)
                        if changes
                            status << changes
                        else
                            errors << changes
                        end
                    end

                    template = File.join(TEMPLATE_DIR, "rock-release-notes.md.template")
                    erb = ERB.new(File.read(template))

                    File.open(File.join(config_dir, Release::RELEASE_NOTES), 'w') do |io|
                        io.write erb.result(binding)
                    end
                end

                desc "prepare RELEASE_NAME", "prepares a new release. It does only local modifications."
                option :branch, doc: "the release branch", type: :string, default: 'stable'
                option :exclude, doc: "the release branch", type: :array, default: []
                option :notes, doc: "whether it should generate release notes", type: :boolean, default: nil
                def prepare(release_name)
                    manifest = ensure_autoproj_initialized
                    packages = all_necessary_packages(manifest)

                    Autoproj.message "Checking out missing packages"
                    packages.each do |pkg|
                        pkg.autobuild.import(checkout_only: true)
                    end

                    excluded_by_user = options[:exclude].flat_map do |entry|
                        entry.split(',')
                    end

                    Autoproj.message "Tagging package sets"
                    failed_package_sets = tag_rock_packages(
                        manifest.each_remote_package_set.map(&:create_autobuild_package),
                        release_name,
                        branch: nil)
                    if !failed_package_sets.empty?
                        raise "failed to prepare #{failed_package_sets.size} package sets"
                    end

                    Autoproj.message "Tagging all Rock-managed packages"
                    # Deal with the packages that are managed within Rock
                    packages_to_tag = packages.find_all do |pkg|
                        !excluded_by_user.include?(pkg.name) && rock_package?(pkg)
                    end
                    failed_packages = tag_rock_packages(
                        packages_to_tag.map(&:autobuild),
                        release_name,
                        branch: options[:branch])
                    if !failed_packages.empty?
                        raise "failed to prepare #{failed_packages.size} packages"
                    end

                    ops = Autoproj::Ops::Snapshot.new(manifest, keep_going: false)
                    versions = ops.snapshot_package_sets +
                        ops.snapshot_packages(packages.map { |pkg| pkg.autobuild.name })
                    versions = ops.sort_versions(versions)

                    version_path = File.join(config_dir, Release::RELEASE_VERSIONS)
                    FileUtils.mkdir_p(File.dirname(version_path))
                    File.open(version_path, 'w') do |io|
                        YAML.dump(versions, io)
                    end
                    Autoproj.message "saved versions in #{version_path}"
                end
            end
        end
    end
end

