module Rock
  
# ERB Templates for Rock::DesignerPluginGenerator (used by rock-create-widget)
module WidgetTemplate

CMAKE = 
%{set(CMAKE_INCLUDE_CURRENT_DIR ON)

SET(MOC_HDRS
    <%= @widget_klassname %>.hpp
    <%= @plugin_klassname %>.hpp
)

SET(HDRS
    <%= @widget_klassname %>.hpp
)

FILE(GLOB SRCS
    *.cpp
)

FILE(GLOB UI_FILES
    *.ui
)

SET(QtApp_RCCS resources.qrc)

rock_vizkit_widget(<%= @widget_klassname %>
    SOURCES ${SRCS} ${QtApp_RCC_SRCS}
    HEADERS ${HDRS}
    MOC ${MOC_HDRS}
    DEPS_PKGCONFIG QtCore QtGui
    UI ${UI_FILES}
)

QT4_ADD_RESOURCES(QtApp_RCC_SRCS ${QtApp_RCCS})

}
# ------------------------------------------------------------------------------

QRC =
%{<!DOCTYPE RCC><RCC version="1.0">
<qresource>
<% if not @icon_path.empty? %>
    <file><%= @icon_path %></file>
<% end %>
</qresource>
</RCC>
}
# ------------------------------------------------------------------------------

PLUGIN_HEADER = 
%{#ifndef <%= @plugin_klassname.upcase %>_HPP
#define <%= @plugin_klassname.upcase %>_HPP

#include <QtGui>
#include <QtDesigner/QDesignerCustomWidgetInterface>

class <%= @plugin_klassname %> : public QObject, public QDesignerCustomWidgetInterface
{
    Q_OBJECT
    Q_INTERFACES(QDesignerCustomWidgetInterface)

public:
    <%= @plugin_klassname %>(QObject *parent = 0);
    virtual ~<%= @plugin_klassname %>();

    bool isContainer() const;
    bool isInitialized() const;
    QIcon icon() const;
    QString domXml() const;
    QString group() const;
    QString includeFile() const;
    QString name() const;
    QString toolTip() const;
    QString whatsThis() const;
    QWidget* createWidget(QWidget *parent);
    void initialize(QDesignerFormEditorInterface *core);

private:
    bool initialized; 
};

#endif /* <%= @plugin_klassname.upcase %>_HPP */  
}
# ------------------------------------------------------------------------------

PLUGIN_SOURCE =
%{#include "<%= @plugin_klassname %>.hpp"
#include "<%= @widget_klassname %>.hpp"

Q_EXPORT_PLUGIN2(<%= @widget_klassname %>, <%= @plugin_klassname %>)

<%= @plugin_klassname %>::<%= @plugin_klassname %>(QObject *parent)
    : QObject(parent)
{
    initialized = false;
}

<%= @plugin_klassname %>::~<%= @plugin_klassname %>()
{
}

bool <%= @plugin_klassname %>::isContainer() const
{
    return false;
}

bool <%= @plugin_klassname %>::isInitialized() const
{
    return initialized;
}

QIcon <%= @plugin_klassname %>::icon() const
{
    return QIcon("<%= @icon_path %>");
}

QString <%= @plugin_klassname %>::domXml() const
{
        return "<ui language=\\"c++\\">\\n"
            " <widget class=\\"<%= @widget_klassname %>\\" name=\\"<%= @widget_klassname.downcase %>\\">\\n"
            "  <property name=\\"geometry\\">\\n"
            "   <rect>\\n"
            "    <x>0</x>\\n"
            "    <y>0</y>\\n"
            "     <width>300</width>\\n"
            "     <height>120</height>\\n"
            "   </rect>\\n"
            "  </property>\\n"
//            "  <property name=\\"toolTip\\" >\\n"
//            "   <string><%= @widget_klassname %></string>\\n"
//            "  </property>\\n"
//            "  <property name=\\"whatsThis\\" >\\n"
//            "   <string><%= @widget_klassname %></string>\\n"
//            "  </property>\\n"
            " </widget>\\n"
            "</ui>\\n";
}

QString <%= @plugin_klassname %>::group() const {
    return "Rock-Robotics";
}

QString <%= @plugin_klassname %>::includeFile() const {
    return "<%= @widget_klassname %>/<%= @widget_klassname %>.hpp";
}

QString <%= @plugin_klassname %>::name() const {
    return "<%= @widget_klassname %>";
}

QString <%= @plugin_klassname %>::toolTip() const {
    return whatsThis();
}

QString <%= @plugin_klassname %>::whatsThis() const
{
    return "<%= @whats_this %>";
}

QWidget* <%= @plugin_klassname %>::createWidget(QWidget *parent)
{
    return new <%= @widget_klassname %>(parent);
}

void <%= @plugin_klassname %>::initialize(QDesignerFormEditorInterface *core)
{
     if (initialized)
         return;
     initialized = true;
}
}
# ------------------------------------------------------------------------------

WIDGET_HEADER =
%{#ifndef <%= @widget_klassname.upcase %>_HPP
#define <%= @widget_klassname.upcase %>_HPP

#include <QtGui>

class <%= @widget_klassname %> : public QWidget
{
    Q_OBJECT
public:
    <%= @widget_klassname %>(QWidget *parent = 0);
    virtual ~<%= @widget_klassname %>();
};

#endif /* <%= @widget_klassname.upcase %>_HPP */
}
# ------------------------------------------------------------------------------

WIDGET_SOURCE =
%{#include "<%= @widget_klassname %>.hpp"

<%= @widget_klassname %>::<%= @widget_klassname %>(QWidget *parent)
    : QWidget(parent)
{
    resize(300,120);

    QLabel *label = new QLabel("Rock 'n Robots!");
    label->setFont(QFont("Verdana", 20));
    label->setAlignment(Qt::AlignCenter);

    QVBoxLayout vbox(this);
    vbox.addWidget(label);
    vbox.setAlignment(Qt::AlignVCenter);

    show();
}

<%= @widget_klassname %>::~<%= @widget_klassname %>()
{
}
}
# ------------------------------------------------------------------------------

WIDGET_TEST_SOURCE =
%{#include <QtGui/QApplication>

#include "<%= @widget_klassname %>.hpp"

int main(int argc, char *argv[]) 
{
    QApplication app(argc, argv);

    <%= @widget_klassname %> <%= @widget_klassname.downcase %>;
    <%= @widget_klassname.downcase %>.show();

    return app.exec();
}
}
# ------------------------------------------------------------------------------

WIDGET_RUBY_INTEGRATION =
%{
Vizkit::UiLoader::extend_cplusplus_widget_class "<%= @widget_klassname %>" do

    #called when the widget is created
    def initialize_vizkit_extension
        #activate Typelib transport via qt slots
        extend Vizkit::QtTypelibExtension
    end

    #called each time vizkit wants to display a new 
    #port with this widget
    def config(value,options)

    end

    #called each time new data are available on the 
    #orocos port connected to the widget the name is
    #custom and can be set via register_widget_for
    def update(sample,port_name)
        #mySlot(sample)
    end
end

# register widget for a specific Typelib type to be 
# accessible via rock tooling (rock-replay,...)
# multiple register_widget_for are allowed for each widget
# Vizkit::UiLoader.register_widget_for("<%= @widget_klassname %>","/base/Angle",:update)
}
# ------------------------------------------------------------------------------
TEST_SCRIPT =
%{
require "vizkit"
widget = Vizkit.default_loader.<%= @widget_klassname %>
widget.show
Vizkit.exec
}
# ------------------------------------------------------------------------------

end
end
