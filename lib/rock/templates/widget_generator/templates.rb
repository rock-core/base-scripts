module Rock
  
# ERB Templates for Rock::DesignerPluginGenerator (used by rock-create-widget)
module WidgetTemplate

CMAKE = 
%{find_package(Qt4 REQUIRED QtCore QtGui QtOpengl QtDesigner)
include_directories(${QT_INCLUDE_DIR})
include_directories(${QT_QTCORE_INCLUDE_DIR})
include_directories(${QT_QTGUI_INCLUDE_DIR})
set(CMAKE_INCLUDE_CURRENT_DIR ON)

SET(MOC_HDRS
    <%= @widget_klassname %>.h
    <%= @plugin_klassname %>.h
)

SET(HDRS
    <%= @widget_klassname %>.h
)

FILE(GLOB SRCS
    *.cc
)

SET(QtApp_RCCS resources.qrc)
QT4_ADD_RESOURCES(QtApp_RCC_SRCS ${QtApp_RCCS})

rock_vizkit_widget(<%= @widget_klassname %>
    SOURCES ${SRCS} ${QtApp_RCC_SRCS} 
    HEADERS ${HDRS}
    MOC ${MOC_HDRS}
    DEPS_PKGCONFIG base-types base-lib QtCore QtGui
    DEPS_CMAKE
    LIBS ${QT_QTCORE_LIBRARY} ${QT_QTGUI_LIBRARY} ${QT_QTOPENGL_LIBRARY} ${QT_QTDESIGNER_LIBRARY}
)

rock_executable(<%= test_binary_name %>
                main.cpp
                DEPS <%= @widget_klassname %>)
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
%{#ifndef <%= @plugin_klassname.upcase %>_H
#define <%= @plugin_klassname.upcase %>_H

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

#endif /* <%= @plugin_klassname.upcase %>_H */  
}
# ------------------------------------------------------------------------------

PLUGIN_SOURCE =
%{#include "<%= @plugin_klassname %>.h"
#include "<%= @widget_klassname %>.h"

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
    return "<%= @widget_klassname %>";
}

QString <%= @plugin_klassname %>::includeFile() const {
    return "<%= @widget_klassname %>/<%= @widget_klassname %>.h";
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
%{#ifndef <%= @widget_klassname.upcase %>_H
#define <%= @widget_klassname.upcase %>_H

#include <QtGui>

class <%= @widget_klassname %> : public QWidget
{
    Q_OBJECT
public:
    <%= @widget_klassname %>(QWidget *parent = 0);
    virtual ~<%= @widget_klassname %>();
};

#endif /* <%= @widget_klassname.upcase %>_H */
}
# ------------------------------------------------------------------------------

WIDGET_SOURCE =
%{#include "<%= @widget_klassname %>.h"

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

#include "<%= @widget_klassname %>.h"

int main(int argc, char *argv[]) 
{
    QApplication app(argc, argv);

    <%= @widget_klassname %> <%= @widget_klassname.downcase %>;
    <%= @widget_klassname.downcase %>.show();

    return app.exec();
}
}
# ------------------------------------------------------------------------------

end
end
