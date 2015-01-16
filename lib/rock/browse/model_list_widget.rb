module Rock
module Browse
class ModelListWidget < Qt::TreeWidget
    attr_reader :loader
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
        loader = OroGen::Loaders::PkgConfig.new(OroGen.orocos_target)
        OroGen::Loaders::RTT.setup_loader(loader)
        loader
    end

    def initialize(parent = nil, loader = self.class.default_loader)
        super(parent)

        @loader = loader

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
        if Orocos.loaded?
            Orocos.clear
        end
        Orocos.load
        populate
    end

    def populate
        if current = current_item
            current_type = current.data(0, Qt::UserRole)
            if current_type.null?
                current = nil
            else
                current_type = current_type.to_int
                current = current.text(0)
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

        Autoproj.manifest.packages.values.sort_by(&:name).each do |pkg|
            role = if File.directory?(pkg.autobuild.srcdir)
                       ROLE_INSTALLED_PACKAGE
                   else
                       ROLE_AVAILABLE_PACKAGE
                   end

            item = Qt::TreeWidgetItem.new(roots[role])
            item.set_text(0, pkg.name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(role))
        end

        Autoproj.manifest.each_package_set.sort_by(&:name).each do |pkg_set|
            item = Qt::TreeWidgetItem.new(roots[ROLE_PACKAGE_SET])
            item.set_text(0, pkg_set.name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(ROLE_PACKAGE_SET))
        end

        Autoproj.osdeps.all_definitions.keys.sort.each do |osdep_name|
            item = Qt::TreeWidgetItem.new(roots[ROLE_OSDEPS])
            item.set_text(0, osdep_name)
            item.set_data(0, Qt::UserRole, Qt::Variant.new(ROLE_OSDEPS))
        end

        if current
            root = roots[current_type]
            matches = findItems(root, Qt::MatchExactly, 0)
            if !matches.empty?
                self.current_item = matches.first
            end
        end
    end
end
end
end

