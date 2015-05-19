module Rock
module Browse
# The main window of rock-browse
class Main < Qt::Widget
    # The page object in which we render
    #
    # @return [MetaRuby::GUI::HTML::Page]
    attr_reader :page

    # The model-list widget that lists all objects
    #
    # @return [ModelListWidget]
    attr_reader :view

    # The set of display (rendering) object
    #
    # There is a one-to-one mapping between the indexes in this array and the
    # Qt::UserRole of the items in {view}. I.e. given an item, item.data(0,
    # Qt::UserRole) is the index of the corresponding renderer.
    #
    # @return [Array<#render>]
    attr_reader :displays

    def initialize(parent = nil)
        super
        create_ui

        @displays = Array.new
        displays[ModelListWidget::ROLE_OROGEN_TYPE] =
            OroGen::HTML::Type.new(page)
        displays[ModelListWidget::ROLE_OROGEN_TASK] =
            OroGen::HTML::TaskContext.new(page)
        displays[ModelListWidget::ROLE_INSTALLED_PACKAGE] =
            Rock::HTML::AutoprojPackage.new(page)
        displays[ModelListWidget::ROLE_AVAILABLE_PACKAGE] =
            Rock::HTML::AutoprojPackage.new(page)
        displays[ModelListWidget::ROLE_PACKAGE_SET] =
            Rock::HTML::AutoprojPackageSet.new(page)
        displays[ModelListWidget::ROLE_OSDEPS] =
            Rock::HTML::AutoprojOSDep.new(page)
    end

    def create_ui
        # Create the UI elements
        main_layout = Qt::VBoxLayout.new(self)
        menu_layout = Qt::HBoxLayout.new
        reload = Qt::PushButton.new("Reload", self)
        menu_layout.add_widget(reload)
        menu_layout.add_stretch(1)

        splitter = Qt::Splitter.new
        main_layout.add_layout(menu_layout)
        main_layout.add_widget(splitter)

        @view = ModelListWidget.new(splitter)
        text = Qt::WebView.new(splitter)
        @page = Page.new(text.page)
        splitter.add_widget(view)
        splitter.add_widget(text)

        # And connect the actions
        reload.connect(SIGNAL('clicked()')) do
            view.reload
        end

        view.connect(SIGNAL('itemClicked(QTreeWidgetItem*,int)')) do |item, col|
            if item and not item.parent.nil?
                render_item(item)
            end
        end

        page.connect(SIGNAL('linkClicked(const QUrl&)')) do |url|
            if url.path == '/rock-browse'
                role = Integer(url.queryItemValue('role'))
                name = url.queryItemValue('name')
                select(name, role)
            end
        end
    end

    def render_item(item)
        role = view.role_from_item(item)
        name = item.text(0)
        render(name, role)
    end

    def select(name, role = nil)
        if item = view.select(name, role)
            render_item(item)
        end
    end

    def render(name, role)
        page.clear
        if role == ModelListWidget::ROLE_OROGEN_TYPE
            Orocos.load_typekit_for(name, false)
            displays[role].render(Orocos.registry.get(name))
        elsif role == ModelListWidget::ROLE_OROGEN_TASK
            model = Orocos.task_model_from_name(name)
            displays[role].render(model)
        elsif role == ModelListWidget::ROLE_INSTALLED_PACKAGE || role == ModelListWidget::ROLE_AVAILABLE_PACKAGE
            package = Autoproj.manifest.packages[name]
            displays[role].render(package)
        elsif role == ModelListWidget::ROLE_PACKAGE_SET
            package = Autoproj.manifest.each_package_set.find { |pkg_set| pkg_set.name == name }
            displays[role].render(package)
        elsif role == ModelListWidget::ROLE_OSDEPS
            osdep = Rock::HTML::OSPackage.new(name)
            displays[role].render(osdep)
        else
            Kernel.raise ArgumentError, "invalid role #{role}"
        end
    end

    def reload
        view.reload
    end
end
end
end

