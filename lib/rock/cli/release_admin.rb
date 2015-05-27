require 'thor'
require 'autoproj'

module Rock
    module CLI
        # Implementation of the rock-release admin subcommand
        class ReleaseAdmin < Thor
            extend Logger::Root("rock-release admin", Logger::INFO)

            namespace 'rock-release:admin'
            class_option :verbose, type: :boolean, default: false
            def self.exit_on_failure?; true end

            attr_reader :config_dir

            ROCK_VCS_LOCATIONS = [
                #/gitorious.*\/rock(?:-[\w-]+)?\//,
                /github.*\/rock(?:-[\w-]+)?\//,
                /github.*\/orocos-toolchain\//]

            def initialize(*args)
                super
                Autoproj.load_config
                Autoproj::CmdLine.initialize_root_directory
                @config_dir = Autoproj.config_dir
                @manifest = ensure_autoproj_initialized
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

            attr_reader :manifest
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


                def rock_package?(package)
                    ROCK_VCS_LOCATIONS.any? { |matcher| matcher === package.vcs.url }
                end

                def tag_rock_packages(packages, release_name, options = Hash.new)
                    options = Kernel.validate_options options, branch: 'stable'
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
                        ReleaseAdmin.warn "the #{pkg_name} package contains uncommitted modifications"
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

                # Guess authors for a package by looking at the git history
                #
                # @option options [50] limit how many git commits should be
                #   considered
                # @option options [Array<(#===,(String,nil)>] mailmap a mapping
                #   from an object matching an email entry to one that should be
                #   used. The matcher is fed strings of the form "User &lt;email&gt;". The
                #   value can be nil to remove an email entry completely.
                # @return [Array<String>,Array<String>] the first returned value
                #   is the list of authors. The entries are of the form "User
                #   &lt;email;&gt;". The second array is a list of warning message
                #   explaining problems that have been found
                def guess_authors_from_git(pkg, options = Hash.new)
                    options = Kernel.validate_options options,
                        limit: 50,
                        mailmap: Array.new
                    importer = pkg.autobuild.importer
                    authors = importer.run_git_bare(pkg.autobuild, "log", "--pretty=format:%aN;%aE", "-#{options[:limit]}")

                    emails, warnings = Array.new, Array.new
                    authors.sort.uniq.each do |git_entry|
                        git_entry = git_entry.encode('UTF-8', undef: :replace)
                        name, email = git_entry.split(';')
                        
                        em, w = filter_email(options[:mailmap], name, email)
                        emails << em
                        warnings << w
                    end
                    emails = emails.compact.sort.uniq
                    warnings = warnings.compact.sort.uniq
                    return emails, warnings
                end

                # Filters an email to make sure it is "clean"
                #
                # @param [Array<(#===,(String,nil)>] mailmap a mapping
                #   from an object matching an email entry to one that should be
                #   used. The matcher is fed strings of the form "User &lt;email&gt;". The
                #   value can be nil to remove an email entry completely.
                # @param [String] the name being filtered
                # @param [String] email the email being filtered
                # @return [(String,nil),(String,nil)] the first returned value
                #   is the filtered email, or nil if this email should not be
                #   used at all. The returned value is of the form "User
                #   &lt;email;&gt;". The second string is a warning message
                #   explaining the filtering
                def filter_email(mailmap, name, email)
                    if email_valid?(email)
                        result = "#{name} <#{email.downcase}>"
                        match = mailmap.find { |matcher, _| matcher === result }
                        if match
                            if !match[1]
                                return nil, "#{result} removed by provided mailmap"
                            else
                                return match[1], "#{result} replaced by #{match[1]} by provided mailmap"
                            end
                        else
                            return result, nil
                        end
                    else
                        return nil, "found invalid email for #{name}: #{email}"
                    end
                end

                def make_emails(enum, mailmap = Array.new)
                    emails, warnings = Array.new, Array.new
                    enum.each do |name, email|
                        if email
                            em, w = filter_email(mailmap, name, email)
                            emails << em
                            warnings << w
                        else
                            warnings << "found #{name} without email"
                        end
                    end
                    emails = emails.compact.sort.uniq
                    warnings = warnings.compact.sort.uniq
                    return emails, warnings
                end

                def email_destination(pkg, mailmap)
                    pkg_manifest = pkg.autobuild.description
                    if !rock_package?(pkg)
                        emails, warnings = make_emails(pkg_manifest.each_rock_maintainer, mailmap)
                        if !emails.empty?
                            return emails, warnings, :maintainers
                        else
                            return [], ["nobody listed as a Rock-side maintainer"], nil
                        end
                    end

                    rock_maintainers, maintainers, authors =
                        make_emails(pkg_manifest.each_rock_maintainer, mailmap),
                        make_emails(pkg_manifest.each_maintainer, mailmap),
                        make_emails(pkg_manifest.each_author, mailmap)
                    warnings = rock_maintainers[1] + maintainers[1] + authors[1]
                    rock_maintainers, maintainers, authors =
                        rock_maintainers[0], maintainers[0], authors[0]
                    if rock_maintainers.empty? && maintainers.empty?
                        if !authors.empty?
                            return authors, warnings, :authors
                        end
                    else
                        return (rock_maintainers + maintainers), warnings, :maintainers
                    end

                    # This is a rock package, chances are, the commit authors
                    # are who we are looking for
                    if pkg.autobuild.importer.kind_of?(Autobuild::Git)
                        authors = guess_authors_from_git(pkg, mailmap: mailmap, limit: 50)
                        if !authors[0].empty?
                            return authors[0], (authors[1] + warnings), :guessed_authors
                        end
                    end

                    return [], ["nobody listed as maintainer, author, and could not extract valid information from the git history"], nil
                end

                def register_maintainer_info(maintainers, pkg, flavor, email_to, warnings, state)
                    m = (maintainers[email_to] ||= Maintainers.new(email_to))
                    prefix = if rock_package?(pkg) then "rock"
                             else "external"
                             end

                    m.send("#{prefix}_#{flavor}_packages") << pkg.name

                    if state == :maintainers
                        m.maintainers_of << pkg.name
                    elsif state == :authors
                        m.authors_of << pkg.name
                    elsif state == :guessed_authors
                        m.guessed_authors_of << pkg.name
                    else
                        raise ArgumentError, "unknown maintainership state #{state}"
                    end
                    if !warnings.empty?
                        m.warnings[pkg.name] = warnings
                    end
                end

                def compute_maintainers(&filter)
                    if options[:mailmap]
                        mailmap = YAML.load(File.read(options[:mailmap]))
                    else
                        mailmap = Hash.new
                    end
                    master_packages = all_necessary_packages(manifest, 'master')
                    if filter
                        master_packages = master_packages.find_all(&filter)
                    end
                    stable_packages = all_necessary_packages(manifest, 'stable')
                    if filter
                        stable_packages = stable_packages.find_all(&filter)
                    end

                    maintainers = Hash.new
                    global_warnings = Hash.new

                    master_packages -= stable_packages
                    master_packages.each do |pkg|
                        email_to, warnings, state = email_destination(pkg, mailmap)
                        if !email_to.empty?
                            register_maintainer_info(maintainers, pkg, 'master',
                                                     email_to, warnings, state)
                        elsif !warnings.empty?
                            global_warnings[pkg.name] = warnings
                        end
                    end
                    stable_packages.each do |pkg|
                        email_to, warnings, state = email_destination(pkg, mailmap)
                        if !email_to.empty?
                            register_maintainer_info(maintainers, pkg, 'stable',
                                                     email_to, warnings, state)
                        elsif !warnings.empty?
                            global_warnings[pkg.name] = warnings
                        end
                    end
                    return maintainers.values, global_warnings
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

            # Information about groups of authors/maintainers and the
            # packages they are responsible for
            #
            class Maintainers < Struct.new(:emails,
                :maintainers_of, :authors_of, :guessed_authors_of,
                :rock_master_packages, :rock_stable_packages,
                :external_master_packages, :external_stable_packages,
                :warnings)

                def initialize(emails)
                    super(emails,
                          Array.new, Array.new, Array.new,
                          Array.new, Array.new,
                          Array.new, Array.new,
                          Hash.new)
                end

                # @!attribute [rw] emails
                #   The list of maintainers emails, formatted as "Name &lt;email&gt;"
                #   @return [[String]] 
                #
                # @!attribute [rw] rock_master_packages 
                #   The name of the master-only packages maintained by this
                #   group of people, that are managed within the Rock
                #   infrastructure
                #   @return [[String]] 
                #
                # @!attribute [rw] rock_stable_packages
                #   The name of the packages present in
                #   stable, maintained by this group of people, that are
                #   managed within the Rock infrastructure
                #   @return [[String]] 
                #
                # @!attribute [rw] external_master_packages
                #   The name of the master-only packages maintained by this
                #   group of people, that are NOT managed within the Rock
                #   infrastructure
                #   @return [[String]] 
                #
                # @!attribute [rw] external_stable_packages
                #   The name of the packages present in stable, maintained by
                #   this group of people, that are NOT managed within the Rock
                #   infrastructure
                #   @return [[String]] 
                #
                # @!attribute [rw] maintainers_of
                #   List of package names for which this group of people are
                #   explicitely declared as maintainers
                #   @return [[String]] 
                #
                # @!attribute [rw] authors_of
                #   List of package names for which this group of people are
                #   declared as authors, and for which no maintainer is
                #   explicitely declared
                #   @return [[String]] 
                #
            end

            DEFAULT_MAILMAP = File.expand_path("release_mailmap.yml", File.dirname(__FILE__))

            desc 'maintainers', 'create a CSV of the package maintainer information'
            option :mailmap, type: :string, default: DEFAULT_MAILMAP
            option :csv, desc: 'display the result as CSV', type: :boolean, default: false
            def maintainer_info
                require 'csv'

                if options[:mailmap]
                    mailmap = YAML.load(File.read(options[:mailmap]))
                else
                    mailmap = Hash.new
                end

                packages  = all_necessary_packages(manifest, 'master')
                packages += all_necessary_packages(manifest, 'stable')
                packages = packages.uniq(&:name).sort_by(&:name)

                info = Array.new
                packages.each do |pkg_def|
                    manifest_xml = pkg_def.autobuild.description
                    if rock_package?(pkg_def)
                        maintainers = make_emails(manifest_xml.each_rock_maintainer.to_a + manifest_xml.each_maintainer.to_a, mailmap)
                        maintainers = maintainers[0] + maintainers[1].map { |msg| "W: #{msg}" }
                        authors     = make_emails(manifest_xml.each_author, mailmap)
                        authors     = authors[0] + authors[1].map { |msg| "W: #{msg}" }
                        git_authors = Array.new
                        if maintainers.empty? && authors.empty?
                            git_authors = guess_authors_from_git(pkg_def, mailmap: mailmap).first
                        end
                    else
                        maintainers = make_emails(manifest_xml.each_rock_maintainer.to_a, mailmap)
                        maintainers = maintainers[0] + maintainers[1].map { |msg| "W: #{msg}" }
                        authors, git_authors = Array.new, Array.new
                    end

                    data = [[pkg_def.name], maintainers, authors, git_authors]
                    line_count = data.map(&:size).max
                    data.each do |arr|
                        arr.concat([""] * (line_count - arr.size))
                    end
                    info.concat(data[0].zip(*data[1..-1]))
                end
                if options[:csv]
                    info.each do |line|
                        puts line.to_csv
                    end
                else
                    info.each do |line|
                        puts line.join(" ")
                    end
                end
            end

            RC_ANNOUNCEMENT_FROM = "Rock Developers <rock-dev@dfki.de>"
            RC_ANNOUNCEMENT_TEMPLATE_PATH = File.expand_path(
                File.join("..", "templates", "rock-release-announce-rc.email.template"),
                File.dirname(__FILE__))

            desc 'announce-rc RELEASE_NAME', 'generates the emails that warn the package maintainers about the RC'
            option :sendgrid_user, type: :string,
                desc: 'the sendgrid user that should be used to access the API to send the emails'
            option :sendgrid_key, type: :string,
                desc: 'the sendgrid key that should be used to access the API to send the emails'
            option :mailmap, desc: "path to a YAML file that maps user/emails as found by rock-release to the actual emails that should be used, see #{DEFAULT_MAILMAP} for an example",
                type: :string, default: DEFAULT_MAILMAP
            def announce_rc(rock_release_name)
                template = ERB.new(File.read(RC_ANNOUNCEMENT_TEMPLATE_PATH), nil, "<>")

                all_maintainers, warnings = compute_maintainers do |pkg|
                    # Only look at packages in rock. rock.core, rock.tutorials
                    # and orocos.toolchain are handled differently
                    pkg.package_set.name == 'rock'
                end

                warnings.each do |pkg_name, w|
                    pkg = manifest.find_package(pkg_name)
                    w.each do |line|
                        ReleaseAdmin.warn "#{pkg.name}: #{line}"
                    end
                end

                package_count = 0
                emails = Array.new
                all_maintainers.each do |m|
                    packages = m.maintainers_of + m.authors_of + m.guessed_authors_of
                    package_count += packages.size
                    subject = "Let's prepare Rock #{rock_release_name}"
                    subject_packages = Array.new
                    remaining = 80 - subject.size - 10
                    while !packages.empty? && (remaining > packages.first.size)
                        subject_packages << packages.shift
                        remaining -= subject_packages.last.size - 2
                    end
                    subject = "#{subject} (#{subject_packages.join(", ")}"
                    if !packages.empty?
                        subject = "#{subject} and #{packages.size} others)"
                    else
                        subject = "#{subject})"
                    end
                    emails << Hash[
                        from: options[:from],
                        to: m.emails,
                        subject: subject,
                        body: template.result(binding).encode('UTF-8', undef: :replace)
                    ]
                end

                if options[:limit]
                    emails = emails[0, [options[:limit], emails.size].min]
                end

                forced_to = options[:to]
                if !options[:sendgrid_user] || !options[:sendgrid_key]
                    ReleaseAdmin.warn "No sendgrid user and key given, saving the emails on disk"
                    emails.each_with_index do |m, i|
                        ReleaseAdmin.info "writing #{i}.txt"
                        File.open("#{i}.txt", 'w') do |io|
                            io.puts "From: #{m[:from]}"
                            io.puts "To: #{forced_to || m[:to].join(", ")}"
                            io.puts "Subject: #{m[:subject]}"
                            io.puts
                            io.write m[:body]
                        end
                    end
                else
                    require 'sendgrid-ruby'
                    client = SendGrid::Client.new(api_user: options[:sendgrid_user], api_key: options[:sendgrid_key])
                    emails.each do |m|
                        email = SendGrid::Mail.new do |em|
                            em.from = m[:from]
                            em.to = Array(forced_to || m[:to])
                            em.subject = m[:subject]
                            em.text = m[:body]
                        end
                        client.send(email)
                    end
                end
                ReleaseAdmin.info "notified maintainers of #{package_count} packages in #{emails.size} emails"
            end

            desc "create-rc", "create a release candidate environment"
            option :branch,  desc: "the release candidate branch", type: :string, default: 'rock-rc'
            option :exclude, desc: "packages on which the RC branch should not be created", type: :array, default: []
            option :update, type: :boolean, default: true, desc: "whether the RC branch should be updated even if it exists or not"
            def create_rc
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
            option :branch, desc: "the release candidate branch", type: :string, default: 'rock-rc'
            def delete_rc
            end

            desc "checkout", "checkout all packages that are included in a given flavor (stable by default). This is done by 'prepare'"
            option 'flavor', type: :string, default: :stable
            def checkout
                Autobuild.do_update = true
                all_necessary_packages(manifest, options[:flavor].to_s).each do |pkg|
                    pkg.autobuild.import(checkout_only: false, only_local: true)
                end
            end

            desc "notes RELEASE_NAME LAST_RELEASE_NAME", "create a release notes file based on the package's changelogs. RELEASE_NAME is the name that will be given to the new release and LAST_RELEASE_NAME the name of an existing release"
            def notes(release_name, last_release_name)
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

            desc "prepare RELEASE_NAME", "Prepare a release: tagging packages and package sets and generating the release's version file. All modifications are local"
            option :branch, desc: "the name of the stable branch", type: :string, default: 'stable'
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

                Autoproj.message "Creating version file, and saving it in #{version_path}"
                ops = Autoproj::Ops::Snapshot.new(manifest, keep_going: false)
                versions = ops.snapshot_package_sets +
                    ops.snapshot_packages(packages.map { |pkg| pkg.autobuild.name })
                versions = ops.sort_versions(versions)

                version_path = File.join(config_dir, Release::RELEASE_VERSIONS)
                FileUtils.mkdir_p(File.dirname(version_path))
                File.open(version_path, 'w') do |io|
                    YAML.dump(versions, io)
                end
                Autoproj.message "Done"
                Autoproj.message "Left to do:"
                Autoproj.message "  - create a release note file in autoproj/#{Release::RELEASE_NOTES}. A template file, created based on the package's changelog, can be created with"
                Autoproj.message "    rock-release admin notes #{release_name} LAST_RELEASE_NAME"
                Autoproj.message "  - commit the build configuration and tag it with the release name"
                Autoproj.message "  - push everything"
                Autoproj.message "  - delete the RC"
            end
        end
    end
end

