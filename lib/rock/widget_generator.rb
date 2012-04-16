#!/usr/bin/env ruby

require 'erb'
require 'fileutils.rb'
require 'rock/templates/widget_generator/templates'

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
        
        def generate(delete_old_files=true)
            generate_files(@data,delete_old_files)
        end
        
    private
    
        def generate_files(data,delete_old_files)
            # Base directory to be created
            @base_path = data.widget_klassname + "/"

            # Source directory for the widget and plugin code
            src_path = @base_path + "src/"

            # path of the vizkit integration script
            vizkit_widget = File.join(src_path,"vizkit_widget.rb")

            # path of the vizkit test script
            test_script = File.join(@base_path,"scripts","test.rb")

            # Widget resource directory
            qrc_path = src_path + "resources/"

            # Use Rock's create library script to initiate the folder structure, the
            # usual set of files and set everything under version control.
            if not(system "rock-create-lib #{@base_path}")
                raise "Failed calling rock-create-lib. Check above for an error message."
            end

            ## Adapt file/folder layout for our purposes.

            begin
                #copy package config file
                package_filename = data.widget_klassname + ".pc.in"
                FileUtils.cp(File.join(src_path, package_filename), File.join(@base_path, package_filename))

                # Source folder. If it already exists: backup by renaming.
                create_folder(src_path,delete_old_files)
                create_folder(qrc_path,delete_old_files)
                remove_file(vizkit_widget,delete_old_files)
                remove_file(test_script,delete_old_files)
                create_folder(File.join(@base_path,"scripts"),delete_old_files)

                FileUtils.mv(File.join(@base_path,package_filename),src_path)

                ## Generate code from templates
                write_file(src_path + "CMakeLists.txt", erb_result(WidgetTemplate::CMAKE, data))
                write_file(src_path + "resources.qrc", erb_result(WidgetTemplate::QRC, data))
                write_file(src_path + "#{data.plugin_klassname}.h", erb_result(WidgetTemplate::PLUGIN_HEADER, data))
                write_file(src_path + "#{data.plugin_klassname}.cc", erb_result(WidgetTemplate::PLUGIN_SOURCE, data))
                write_file(src_path + "#{data.widget_klassname}.h", erb_result(WidgetTemplate::WIDGET_HEADER, data))
                write_file(src_path + "#{data.widget_klassname}.cc", erb_result(WidgetTemplate::WIDGET_SOURCE, data))
                write_file(vizkit_widget, erb_result(WidgetTemplate::WIDGET_RUBY_INTEGRATION, data))
                write_file(test_script, erb_result(WidgetTemplate::TEST_SCRIPT, data))

            rescue SystemCallError => err
                puts "SystemCallError: '#{err.message}'. You should delete the possibly generated directory '#{@base_path}' before starting over."
            end

        end
        
        # Fills template with data, parses template and returns result string.
        def erb_result(template, data)
            ERB.new(template, nil, "%<>").result(data.get_binding)
        end

        def write_file(path, content)
            file = File.new(path, File::WRONLY|File::CREAT|File::EXCL)
            file.write content
            file.close
        end
        
        #removes the file or renames it to file.old if delete_file =false
        def remove_file(name,delete_file)
            if File.exist?(name)
                if delete_file
                    FileUtils.rm_r(name)
                else
                    FileUtils.mv(name, File.basename(name)+".old")
                end
            end
        end

        def create_folder(name,delete_directory)
            if File.exist?(name)
                if delete_directory
                    FileUtils.rm_r(name)
                else
                    FileUtils.mv(name,name+".old")
                end
            end
            Dir.mkdir(name)
        end

    end

    private

    # Template data
    # Contains relevant information the widget and designer plugin to be generated.
    class DesignerPluginData
        attr_reader :plugin_klassname
        attr_reader :widget_klassname
        attr_reader :test_binary_name
        attr_reader :icon_path
        attr_reader :whats_this

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
