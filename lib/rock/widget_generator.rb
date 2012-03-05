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
        require 'rock/templates/widget_generator/templates'
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
          old_src_path = src_path.chop + old_folder_suffix
          
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
              FileUtils.mv(src_path, old_src_path)
            end
            Dir.mkdir(src_path)
            
            # Copy package file (.pc.in) back to src folder
            package_filename = data.widget_klassname + ".pc.in"
            if File.exist?(old_src_path + package_filename)
              FileUtils.mv(old_src_path + package_filename, src_path + package_filename)
            end

            # Resource folder. If it already exists: backup by renaming.
            if File.exist?(qrc_path)
              FileUtils.mv(qrc_path, qrc_path.chop + old_folder_suffix)
            end
            Dir.mkdir(qrc_path)

            ## Generate code from templates
            write_file(src_path + "CMakeLists.txt", erb_result(WidgetTemplate::CMAKE, data))
            write_file(src_path + "resources.qrc", erb_result(WidgetTemplate::QRC, data))
            write_file(src_path + "#{data.plugin_klassname}.h", erb_result(WidgetTemplate::PLUGIN_HEADER, data))
            write_file(src_path + "#{data.plugin_klassname}.cc", erb_result(WidgetTemplate::PLUGIN_SOURCE, data))
            write_file(src_path + "#{data.widget_klassname}.h", erb_result(WidgetTemplate::WIDGET_HEADER, data))
            write_file(src_path + "#{data.widget_klassname}.cc", erb_result(WidgetTemplate::WIDGET_SOURCE, data))
            write_file(src_path + "main.cpp", erb_result(WidgetTemplate::WIDGET_TEST_SOURCE, data))
            
          rescue SystemCallError => err
            puts "SystemCallError: '#{err.message}'. You should delete the possibly generated directory '#{@base_path}' before starting over."
          end
          
        end
        
        def erb_result(template, data)
          ERB.new(template, nil, "%<>").result(data.get_binding)
        end

        def write_file(path, content)
            file = File.new(path, File::WRONLY|File::CREAT|File::EXCL)
            file.write content
            file.close
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
