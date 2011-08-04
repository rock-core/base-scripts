require 'vizkit'
require'orocos'

module Rock
    class SearchItem
        attr_reader :object
        attr_accessor :project_name
        attr_reader :name
        def initialize(*info)
            if info.size != 1
                raise 'Wrong number of arguments'
            end
            info = info[0]
            @object = info[:object]
            @project_name = info[:project_name]
            @name = info[:name]
        end

        def eql?(obj)
            self == obj 
            name == obj.name
        end

        def hash
            name.hash
        end

        def ==(obj)
            name == obj.name
        end
    end

    class Inspect
        class << self
            attr_accessor :debug
        end

        Inspect::debug = false
        Orocos.load
        @master_project = Orocos::Generation::Project.new

        def self.load_orogen_project(master_project, name, debug)
            master_project.load_orogen_project(name)
        rescue Exception => e
            if Rock::Inspect::debug
                raise
            end
            STDERR.puts "WARN: cannot load the installed oroGen project #{name}"
            STDERR.puts "WARN:     #{e.message}"
        end

        def self.find(pattern,filter = Hash.new)
            tasks = Array.new
            types = Array.new
            deployments = Array.new
            ports = Array.new
            widgets = Array.new

            #search for types
            #we are not searching for types all the time 
            if((filter.has_key?(:types) && filter.size == 1 && pattern.empty?) ||
               (filter.empty? && !pattern.empty?))
                reg = filter.has_key?(:types) ? filter[:types] : pattern
                types = Rock::Inspect::find_types(/#{reg}/,filter)
            end

            #search for ports
            if((!filter.has_key?(:deployments) && !filter.has_key?(:tasks) && 
                (filter.has_key?(:ports)||filter.has_key?(:types)))|| 
                (filter.empty? && !pattern.empty?))
                reg = filter.has_key?(:ports) ? filter[:ports] : pattern
                ports = Rock::Inspect::find_ports(/#{reg}/,filter)
            end

            #search for tasks
            if((!filter.has_key?(:deployments) && 
                (filter.has_key?(:tasks) || filter.has_key?(:ports) || filter.has_key?(:types))) || 
                (filter.empty? && !pattern.empty?))
                reg = filter.has_key?(:tasks) ? filter[:tasks] : pattern
                tasks = Rock::Inspect::find_tasks(/#{reg}/, filter)
            end

            #search for deployments
            if(filter.has_key?(:deployments) ||
               filter.has_key?(:ports)  ||
               filter.has_key?(:tasks)  ||
               filter.has_key?(:types)  ||
               (filter.empty? && !pattern.empty?))
                reg = filter.has_key?(:deployments) ? filter[:deployments] : pattern
                reg = /./ unless reg
                puts reg
                deployments = Rock::Inspect::find_deployments(/#{reg}/,filter)
            end

            #search for widgets
            if((!filter.has_key?(:deployments) && !filter.has_key?(:tasks) &&
                !filter.has_key?(:ports) && !filter.has_key?(:plugins)) ||
                (filter.empty? && !pattern.empty?))
                reg = filter.has_key?(:widgets) ? filter[:widgets] : pattern
                widgets = Rock::Inspect::find_widgets(/#{reg}/, filter)
            end

            result =  deployments + tasks + ports + types + widgets
            result.uniq.sort_by{|t|t.name}
        end

        def self.find_tasks(pattern,filter = Hash.new)
            found = []
            #find all tasks which are matching the pattern
            Orocos.available_task_models.each do |name, project_name|
                if name =~ pattern || project_name =~ pattern
                    if tasklib = load_orogen_project(@master_project, project_name, Rock::Inspect::debug)
                        task = tasklib.self_tasks.find { |t| t.name == name }
                        if(task_match?(task,pattern,filter))
                            found << SearchItem.new(:name => "TaskContext::#{task.name}",
                                                    :project_name => project_name,
                                                        :object => task)
                        end
                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_ports(pattern,filter = Hash.new)
            found = []
            #find all tasks which are matching the pattern
            Orocos.available_task_models.each do |name, project_name|
                if tasklib = load_orogen_project(@master_project, project_name, Rock::Inspect::debug)
                    tasklib.self_tasks.each do |task|
                        task.each_port do |port|
                            if(port_match?(port,pattern,filter))
                                found <<  SearchItem.new(:name => "Port::#{port.name}",
                                                         :project_name => project_name,
                                                             :object => port)
                                                         break
                            end
                        end
                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_types(pattern,filter = Hash.new)
            found = Array.new
            Orocos.available_projects.each_key do |project_name|
                seen = Set.new
                next if !@master_project.has_typekit?(project_name)

                project = load_orogen_project(@master_project, project_name, Rock::Inspect::debug)
                next if !project
                typekit = project.typekit
                matching_types = typekit.typelist.grep(pattern)
                if !matching_types.empty?
                    @master_project.using_typekit(project_name)
                    matching_types.each do |type_name|
                        if !seen.include?(type_name)
                            object = @master_project.find_type(type_name)
                            if type_match?(object,pattern,filter)
                                found << SearchItem.new(:name => "Type::#{type_name}",
                                                        :project_name => project_name,
                                                            :object => object)
                            end
                            seen << type_name
                        end
                    end
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.find_deployments(pattern,filter=Hash.new)
            found = []
            Orocos.available_deployments.each do |name, pkg|
                project_name = pkg.project_name
                if name =~ pattern || project_name =~ pattern
                    if tasklib = load_orogen_project(@master_project, project_name, Rock::Inspect::debug)
                        if deployer = tasklib.deployers.find {|n| n.name == name}
                            if deployment_match?(deployer,pattern,filter)
                                found << SearchItem.new(:name => "Deployment::#{deployer.name}",
                                                        :project_name => project_name,
                                                            :object => deployer)
                            end
                        end
                    end
                end
            end
            found.sort_by{|t|t.name}
        end


        def self.find_plugins(pattern,filter = Hash.new)

        end
        def self.find_widgets(pattern,filter=Hash.new)
            found = []
            widgtes = Vizkit.default_loader.available_widgets
            widgtes.each do |widget|
                if widget_match?(widget,pattern,filter)
                    #we do not want to create an instance of the widget here
                    #use a Qt Widget as dummy
                    found << SearchItem.new(:name => widget, :object => Qt::Widget.new)
                end
            end
            found.sort_by{|t|t.name}
        end

        def self.deployment_match?(deployment,pattern,filter = Hash.new)
            return false if (!(deployment.name =~ pattern))
            return false if (filter.has_key?(:deployments) && !(deployment.name =~ filter[:deployments]))
            return false if (deployment.task_activities.all?{|t| !( task_match?(t.task_model,//,filter))})
            true
        end

        def self.type_match?(type,pattern,filter = Hash.new)
            true
        end

        def self.widget_match?(widget,pattern,filter = Hash.new)
            return false unless widget =~ pattern
            if filter.has_key?(:types)
                has_type = false
                Vizkit.default_loader.registered_for(widget).each do |type|
                    has_type = true if(type =~ filter[:types])
                end
                return false if !has_type
            end
            true
        end

        def self.port_match?(port,pattern,filter = Hash.new)
            return false if (!(port.name =~ pattern) && !(port.type_name =~ pattern))
            return false if (filter.has_key?(:tasks) && !(port.task.name =~ filter[:tasks]))
            return false if (filter.has_key?(:ports) && !(port.name =~ filter[:ports]))
            return false if (filter.has_key?(:types) && !(port.type_name =~ filter[:types]))
            true
        end

        def self.task_match?(task,pattern,filter= Hash.new)
            return false unless task.name =~ pattern
            return false if(filter.has_key?(:tasks) && !(task.name =~ filter[:tasks]))
            has_port = false
            #we have to disable the filter :task otherwise there will be trouble with subclasses
            old = filter.delete :tasks
            task.each_port {|port| has_port = true if(port_match?(port,//,filter))}
            return false if !has_port
            filter[:tasks] = old if old
            if filter.has_key? :types
                has_type= false
                task.each_port {|port| has_type = true if(port.type_name =~ filter[:types])}
                task.each_property {|property| has_type = true if(property.type_name.to_s =~ filter[:types])}
                task.each_attribute {|attribute| has_type = true if(attribute.type_name.to_s =~ filter[:types])}
                return false if !has_type
            end
            #return false if(filter.has_key?(:deployments) && !(task.name =~ filter[:tasks]))
            true
        end
    end

    class GenericView
        attr_reader :name

        def initialize(search_item)
            obj = search_item.object
            @name = search_item.name
            @project_name = search_item.project_name
            @object = obj
            @header = "Name:"
            @header2 = nil
        end

        def hash
            @name.hash
        end

        def eql?(obj)
            self == obj
        end

        def ==(obj)
            @name == obj.name
        end

        def pretty_print(pp)
            pp.text "=========================================================="
            pp.breakable
            pp.text "#{@header} #{@name}"
            pp.breakable
            pp.text "defined in #{@project_name}"
            pp.breakable
            if @header2
                pp.text "#{@header2}"
                pp.breakable
            end
            pp.text "----------------------------------------------------------"
            if((@object && @object.respond_to?(:pretty_print)))
                pp.breakable
                pp.nest(2) do 
                    pp.breakable
                    @object.pretty_print(pp)
                end
            end
            pp.breakable
        end
    end

    class WidgetView < GenericView
        def initialize(search_item)
            super
            @header = "Widget name: "
        end

        def pretty_print(pp)
            extension = Vizkit.default_loader.cplusplus_extension_hash[@name]
            ruby_widget_new = Vizkit.default_loader.ruby_widget_hash[@name]
            pp.text "=========================================================="
            pp.breakable
            pp.text "#{@header} #{@name}"
            pp.breakable
            if !ruby_widget_new
                pp.text "C++ Widget"
            else
                pp.text "Ruby Widget"
            end
            pp.breakable
            Vizkit.default_loader.registered_for(@name).each do |val|
                pp.text "registerd for: #{val}"
                pp.breakable
            end
            pp.text "----------------------------------------------------------"
            pp.breakable

            if extension 
                pp.breakable
                extension.instance_methods.each do |method|
                    pp.text "added ruby method: #{method.to_s}"
                    pp.text "(#{extension.instance_method(method).arity} parameter)"
                    pp.breakable
                end
            else
                if !ruby_widget_new
                    pp.text "no ruby extension"
                    pp.breakable
                else
                    methods = Qt::Widget.instance_methods
                    klass = ruby_widget_new.call.class
                    klass.instance_methods.each do |method|
                        if !methods.include? method
                            pp.text "ruby method: #{method.to_s}"
                            pp.text "(#{klass.instance_method(method).arity} parameter)"
                            pp.breakable
                        end
                    end
                end
            end
        end

    end

    class DeploymentView < GenericView
        def initialize(search_item)
            super
            @header = "Deployment name: "
        end
    end

    class TypeView < GenericView
        def initialize(search_item)
            super
            @header = "Typelib name: "
        end
    end

    class PortView < GenericView
        def initialize(search_item)
            super
            @header = "Port name: "
            @header2 = "defined in Task #{search_item.object.task.name}"
        end
    end

    class TaskView < GenericView
        attr_reader :name
        def initialize(search_item)
            obj = search_item.object
            obj = obj.task if obj.is_a? Orocos::Spec::Port

            @name = obj.name
            @project_name = search_item.project_name
            @object = obj
            @header = "Task name: "
        end
    end

    class PluginView

    end
end
