require 'thor'
require 'autoproj'

module Rock
    module CLI
        # Implementation of the rock-release admin subcommand
        class ReleaseAdmin < Thor
            namespace 'rock-release:admin'
            class_option :verbose, type: :boolean, default: false
            def self.exit_on_failure?; true end

            attr_reader :config_dir

            ROCK_VCS_LOCATIONS = [
                /gitorious.*\/rock(?:-[\w-]+)?\//,
                /github.*\/rock(?:-[\w-]+)?\//,
                /github.*\/orocos-toolchain\//]

            def initialize(*args)
                super
                Autoproj.load_config
                Autoproj::CmdLine.initialize_root_directory
                @config_dir = Autoproj.config_dir
                @manifest = Autoproj.manifest
            end

            no_commands do
                def invoke_command(*args, &block)
                    super
                rescue Exception => e
                    Autoproj.error "#{e.message} (#{e.class})"
                    if options[:verbose]
                        e.backtrace.each do |bt|
                            Autoproj.error "  #{bt}"
                        end
                    end
                    exit 1
                end

                # Returns all packages that are necessary within the created
                # release
                def all_necessary_packages(manifest, flavor = 'stable')
                    manifest.each_package_definition.find_all do |pkg|
                        Rock.flavors.package_in_flavor?(pkg.name, flavor)
                    end
                end

                def ensure_autoproj_initialized
                    if !Autoproj.manifest
                        if options[:verbose]
                            Autoproj::CmdLine.initialize_and_load([])
                        else
                            Autoproj.silent do
                                Autoproj::CmdLine.initialize_and_load([])
                            end
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

                def email_valid?(email)
                    true
                end

                def filter_email(pkg, mailmap, name, email)
                    if email_valid?(email)
                        result = "#{name} <#{email.downcase}>"
                        match = mailmap.find { |matcher, _| matcher === result }
                        if match
                            if !match[1]
                                pkg.autobuild.warn "%s: obsolete entry #{result} (removed by provided mailmap)"
                                nil
                            else
                                match[1]
                            end
                        else
                            result
                        end
                    else
                        pkg.autobuild.warn "%s: found invalid email for #{name}: #{email}"
                        nil
                    end
                end

                def make_emails(pkg, enum, mailmap)
                    enum.map do |name, email|
                        if email
                            filter_email(pkg, mailmap, name, email)
                        else
                            pkg.autobuild.message "%s: found #{name} without email"
                            nil
                        end
                    end.compact.sort.uniq
                end

                def email_destination(pkg, mailmap)
                    pkg_manifest = pkg.autobuild.description
                    if !rock_package?(pkg)
                        if !(email_to = make_emails(pkg, pkg_manifest.each_rock_maintainer, mailmap)).empty?
                            return email_to, true
                        else
                            pkg.autobuild.error "%s: nobody listed as a Rock-side maintainer"
                            return
                        end
                    end

                    rock_maintainers, maintainers, authors =
                        make_emails(pkg, pkg_manifest.each_rock_maintainer, mailmap),
                        make_emails(pkg, pkg_manifest.each_maintainer, mailmap),
                        make_emails(pkg, pkg_manifest.each_author, mailmap)
                    if rock_maintainers.empty? && maintainers.empty?
                        if !authors.empty?
                            return authors, false
                        end
                    else
                        return rock_maintainers + maintainers, true
                    end

                    # This is a rock package, chances are, the commit authors
                    # are who we are looking for
                    importer = pkg.autobuild.importer
                    if importer.kind_of?(Autobuild::Git)
                        authors = importer.run_git_bare(pkg.autobuild, "log", "--pretty=format:%aN;%aE", "-50")
                        authors = authors.sort.uniq.map do |git_entry|
                            name, email = git_entry.split(';')
                            filter_email(pkg, mailmap, name, email)
                        end.compact.sort.uniq
                        if !authors.empty?
                            return authors, false
                        end
                    end

                    pkg.autobuild.error "%s: nobody listed as maintainer, author, and could not extract valid information from the git history"
                end

                def compute_maintainers
                    if options[:mailmap]
                        mailmap = YAML.load(File.read(options[:mailmap]))
                    else
                        mailmap = Hash.new
                    end
                    manifest = ensure_autoproj_initialized
                    master_packages = all_necessary_packages(manifest, 'master')
                    stable_packages = all_necessary_packages(manifest, 'stable')

                    maintainers = Hash.new

                    master_packages -= stable_packages
                    master_packages.each do |pkg|
                        email_to, is_maintainer = email_destination(pkg, mailmap)
                        if email_to
                            email_to = email_to.sort
                            m = (maintainers[email_to] ||= Maintainers.new(email_to, Hash.new, Hash.new))
                            m.master_packages[pkg] ||= is_maintainer
                        end
                    end
                    stable_packages.each do |pkg|
                        email_to, is_maintainer = email_destination(pkg, mailmap)
                        if email_to
                            email_to = email_to.sort
                            m = (maintainers[email_to] ||= Maintainers.new(email_to, Hash.new, Hash.new))
                            m.stable_packages[pkg] ||= is_maintainer
                        end
                    end
                    maintainers
                end

                def join_and_cut_at_70chars(array, indentation)
                    result = Array.new
                    line_size = 0
                    line = Array.new

                    target_w = 70 - indentation
                    array.each do |entry|
                        if line_size + entry.size + (line.size - 1) * 2 >= target_w
                            result << line.join(", ")
                            line_size = 0
                            line.clear
                        end
                        line << entry
                        line_size += entry.size
                    end
                    if !line.empty?
                        result << line.join(", ")
                    end
                    result.join("\n" + " " * indentation)
                end
            end

            Maintainers = Struct.new :emails, :master_packages, :stable_packages

            DEFAULT_MAILMAP = File.expand_path("release_mailmap.yml", File.dirname(__FILE__))

            desc 'maintainers', 'lists the known maintainers along with the packages they maintain'
            option :mailmap, type: :string, default: DEFAULT_MAILMAP
            def maintainers
                maintainers = compute_maintainers

                flat_maintainers = Hash.new
                maintainers.each do |_, m|
                    m.emails.each do |em|
                        flat_maintainers[em] ||= [Array.new, Array.new]
                        flat_maintainers[em][0].concat(m.master_packages.keys)
                        flat_maintainers[em][1].concat(m.stable_packages.keys)
                    end
                end

                flat_maintainers.sort_by { |em, _| em }.each do |email, (master, stable)|
                    puts "#{email}:"
                    puts "  #{master.size} master packages: #{master.map(&:name).sort.join(", ")}"
                    puts "  #{stable.size} stable packages: #{stable.map(&:name).sort.join(", ")}"
                end
            end

            RC_ANNOUNCEMENT_FROM = "Rock Developers <rock-dev@dfki.de>"
            RC_ANNOUNCEMENT_TEMPLATE_PATH = File.expand_path(
                File.join("..", "templates", "rock-release-announce-rc.email.template"),
                File.dirname(__FILE__))

            desc 'announce-rc RELEASE_NAME', 'generates the emails that warn the package maintainers about the RC'
            option :mailmap, type: :string, default: DEFAULT_MAILMAP
            def announce_rc(rock_release_name)
                template = ERB.new(File.read(RC_ANNOUNCEMENT_TEMPLATE_PATH), nil, "<>")
                compute_maintainers.each_value do |m|
                    from = RC_ANNOUNCEMENT_FROM
                    to = m.emails
                    maintainers_of = m.master_packages.find_all { |_, m| m } +
                        m.stable_packages.find_all { |_, m| m }
                    maintainers_of = maintainers_of.map { |p, _| p.name }
                    authors_of = m.master_packages.find_all { |_, m| !m } +
                        m.stable_packages.find_all { |_, m| !m }
                    authors_of = authors_of.map { |p, _| p.name }
                    master_packages = m.master_packages.keys.map(&:name).sort
                    stable_packages = m.stable_packages.keys.map(&:name).sort
                    puts template.result(binding)
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
                # We checkout and branch all packages, not only the stable
                # ones, to ease release of new packages. This does not mean
                # that we're going to release all of them, of course !
                packages = all_necessary_packages(manifest, 'master')

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
                        reference_branch =
                            if Rock.flavors.package_in_flavor?(pkg.name, 'stable')
                                'stable'
                            else 'master'
                            end
                        pkg.importer.run_git_bare(pkg, 'push', 'autobuild', "+refs/remotes/autobuild/#{reference_branch}:refs/heads/#{branch}")
                    end
                    versions << Hash[pkg.name => Hash['branch' => branch]]
                end
                ops = Autoproj::Ops::Snapshot.new(manifest)
                versions += ops.snapshot_packages(packages_to_snapshot.map { |pkg| pkg.autobuild.name })

                vcs = Autoproj::VCSDefinition.from_raw(Release::ROCK_RELEASE_INFO)
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

            desc "delete-rc", "delete a release candidate environment created with create-rc"
            option :branch, doc: "the release candidate branch", type: :string, default: 'rock-rc'
            def delete_rc
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

