module Rock
module Browse
class ModelListWidget < Qt::TreeWidget
    attr_reader :loader
    attr_reader :manifest
    attr_reader :osdeps
    attr_reader :roots

    #--
    # !!! DON'T FORGET TO CHANGE THE INITIALIZATION OF {Main#displays} in
    # {Main#initialize} AS WELL AS {ROLE_NAMES} (below) if you change those
    #++
    ROLE_OROGEN_TYPE = 0
    ROLE_OROGEN_TASK = 1
    ROLE_INSTALLED_PACKAGE = 2
    ROLE_AVAILABLE_PACKAGE = 3
    ROLE_PACKAGE_SET = 4
    ROLE_OSDEPS = 5

    ROLE_NAMES = [
        "oroGen Types",
        "oroGen Tasks",
        "Installed Packages",
        "Available Packages",
        "Package Sets",
        'OS Packages'
    ]

    def self.default_loader
        OroGen::Loaders::RTT.new(OroGen.orocos_target)
    end

    def initialize(parent = nil,
                   loader = self.class.default_loader,
                   manifest = Autoproj.manifest,
                   osdeps = Autoproj.osdeps)
        super(parent)

        @loader = loader
        @manifest = manifest
        @osdeps = osdeps

        @roots = Array.new
        ROLE_NAMES.each_with_index do |name, i|
            roots[i] = Qt::TreeWidgetItem.new(self)
            roots[i].set_text(0, name)
        end
        set_header_label("")
    end

    def clear
        roots.each(&:take_children)
    end

    def reload
        loader.clear
        populate
    end

    def populate
        if current = current_item
            current_type = current.data(0, Qt::UserRole)
            if current_type.null?
                current_name = nil
            else
                current_type = current_type.to_int
                current_name = current.text(0)
            end
        end
        clear
        
        loader.available_types.keys.sort.each do |name|
            item = Qt::TreeWidgetItem.new(roots[ROLE_OROGEN_TYPE])
            item.set_text(0, name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(ROLE_OROGEN_TYPE))
        end

        loader.available_task_models.keys.sort.each do |name|
            item = Qt::TreeWidgetItem.new(roots[ROLE_OROGEN_TASK])
            item.set_text(0, name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(ROLE_OROGEN_TASK))
        end

        manifest.packages.values.sort_by(&:name).each do |pkg|
            role = if File.directory?(pkg.autobuild.srcdir)
                       ROLE_INSTALLED_PACKAGE
                   else
                       ROLE_AVAILABLE_PACKAGE
                   end

            item = Qt::TreeWidgetItem.new(roots[role])
            item.set_text(0, pkg.name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(role))
        end

        manifest.each_package_set.sort_by(&:name).each do |pkg_set|
            item = Qt::TreeWidgetItem.new(roots[ROLE_PACKAGE_SET])
            item.set_text(0, pkg_set.name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(ROLE_PACKAGE_SET))
        end

        osdeps.all_definitions.keys.sort.each do |osdep_name|
            item = Qt::TreeWidgetItem.new(roots[ROLE_OSDEPS])
            item.set_text(0, osdep_name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(ROLE_OSDEPS))
        end

        if current_type && current_name
            select(current_type, current_name)
        end
    end

    def role_from_item(item)
        role = item.data(0, Qt::UserRole)
        if !role.null?
            role.to_int
        end
    end

    def select(name, role = nil)
        matches = findItems(name, Qt::MatchExactly | Qt::MatchRecursive, 0)
        if role
            single_match = matches.find do |item|
                role == role_from_item(item)
            end
        else single_match = matches.first
        end

        if single_match
            self.current_item = single_match
        end
    end
end
end
end

