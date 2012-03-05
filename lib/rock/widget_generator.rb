#!/usr/bin/env ruby

require 'erb'
require 'fileutils.rb'

module Rock

    # Widget and Designer Plugin Generator
    # 
    # This program generates the essential source and header files needed to
    # implement a Qt4 Widget. A plugin for Qt Designer is being prepared as well.
    #
    # @author Allan E. Conquest - allan.conquest@dfki.de
    #
    class DesignerPluginGenerator
        @data = nil
        
        def initialize( widget_klassname, icon_path, whats_this )
            @data = DesignerPluginData::new(widget_klassname, icon_path, whats_this)
        end
        
        def generate
            generate_files(@data)
        end
        
    private        
    
        def generate_files(data)
          # Base directory to be created
          @base_path = data.widget_klassname + "/"
          
          # Source directory for the widget and plugin code
          src_path = @base_path + "src/"
          
          # How to rename an already existing folder
          old_folder_suffix = ".old/"
          
          # Widget resource directory
          qrc_path = src_path + "resources/"
          
          # Use Rock's create library script to initiate the folder structure, the
          # usual set of files and set everything under version control.
          if not(system "rock-create-lib #{@base_path}")
            raise "Failed calling rock-create-lib. Check above for an error message. Did you forget to source your env.sh?"
          end
          
          ## Adapt file/folder layout for our purposes.
          
          file = nil
          
          begin
            # Source folder. If it already exists: backup by renaming.
            if File.exist?(src_path)
              FileUtils.mv(src_path, src_path.chop + old_folder_suffix)
            end
            Dir.mkdir(src_path)

            # Resource folder. If it already exists: backup by renaming.
            if File.exist?(qrc_path)
              FileUtils.mv(qrc_path, qrc_path.chop + old_folder_suffix)
            end
            Dir.mkdir(qrc_path)

            ## Generate code from templates

            # CMake
            write_file(src_path + "CMakeLists.txt", generate_cmake(data))

            # Resources
            write_file(src_path + "resources.qrc", generate_qrc(data))

            # Plugin header
            write_file(src_path + "#{data.plugin_klassname}.h", generate_plugin_header(data))

            # Plugin source
            write_file(src_path + "#{data.plugin_klassname}.cc", generate_plugin_source(data))

            # Widget header
            write_file(src_path + "#{data.widget_klassname}.h", generate_widget_header(data))

            # Widget source
            write_file(src_path + "#{data.widget_klassname}.cc", generate_widget_source(data))

            # Widget test source
            write_file(src_path + "main.cpp", generate_widget_test_source(data))
            
          rescue SystemCallError => err
            puts "SystemCallError: '#{err.message}'. You should delete the possibly generated directory '#{@base_path}' before starting over."
          end
          
        end
        
        def erb_result(template, data)
          ERB.new(template).result(data.get_binding)
        end

        def write_file(path, content)
            file = File.new(path, File::WRONLY|File::CREAT|File::EXCL)
            file.write content
            file.close
        end

        def generate_cmake(data)
          template_cmake = 
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
            }.gsub(/^            /, '') # kill first 4 blanks in template
            erb_result(template_cmake, data)
        end

        def generate_qrc(data)
          template = 
          %{<!DOCTYPE RCC><RCC version="1.0">
            <qresource>
                <% if not @icon_path.empty? %>
                    <file><%= @icon_path %></file>
                <% end %>
            </qresource>
            </RCC>
          }.gsub(/^            /, '') # kill first 4 blanks in template
          erb_result(template, data)
        end

        def generate_plugin_header(data)
          template_header = 
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
          }.gsub(/^            /, '') # kill first 4 blanks in template
          erb_result(template_header, data)
        end

        def generate_plugin_source(data)
          template_src = 
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
          }.gsub(/^            /, '') # kill first 4 blanks in template
          erb_result(template_src, data)
        end

        def generate_widget_header(data)
          template = 
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
            
          }.gsub(/^            /, '') # kill first 4 blanks in template
          erb_result(template, data)
        end

        def generate_widget_source(data)
          template = 
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
          }.gsub(/^            /, '') # kill first 4 blanks in template
          erb_result(template, data)
        end

        def generate_widget_test_source(data)
          template = 
          %{#include <QtGui/QApplication>

            #include "<%= @widget_klassname %>.h"

            int main(int argc, char *argv[]) 
            {
                QApplication app(argc, argv);

                <%= @widget_klassname %> <%= @widget_klassname.downcase %>;
                <%= @widget_klassname.downcase %>.show();

                return app.exec();
            }
          }.gsub(/^            /, '') # kill first 4 blanks in template
          erb_result(template, data)
        end
    end
    
private

    # Template data
    # Contains relevant information about the designer plugin to be generated.
    class DesignerPluginData
      attr_reader :plugin_klassname
      attr_reader :widget_klassname
      attr_reader :test_binary_name
      attr_reader :icon_path
      attr_reader :whats_this
      
      @base_path = nil
      
      def initialize( widget_klassname, icon_path, whats_this )
        @widget_klassname = widget_klassname
        @plugin_klassname = widget_klassname + "Plugin"
        @test_binary_name = widget_klassname.downcase + "Test"
        @icon_path = icon_path
        @whats_this = whats_this
      end
      
      # Support templating
      def get_binding
        binding
      end
      
    end
end
