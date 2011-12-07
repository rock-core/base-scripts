require 'erb'
module Rock
    module Doc
        module HTML
            TEMPLATE_DIR = File.expand_path(File.join('templates', 'html'), File.dirname(__FILE__))

            class << self
                attr_reader :templates
            end
            @templates = Hash.new

            def self.load_template(full_path)
                if template = @templates[full_path]
                    return template
                end
                @templates[full_path] = ERB.new(File.read(full_path), nil, nil, full_path.gsub(/[\/\.-]/, '_'))
            end

            def self.template_path(*relpath)
                if relpath.empty?
                    TEMPLATE_DIR
                else
                    File.expand_path(File.join(*relpath), TEMPLATE_DIR)
                end
            end

            def self.render_template(*path)
                binding = path.pop
                path = template_path(*path)
		template = load_template(path)
                template.result(binding)
            end

            def self.rendering_context_for(object)
                case object
                when Orocos::Spec::TaskContext
                    TaskRenderingContext.new(object)
                else
                    RenderingContext.new(object)
                end
            end

            def self.render_object(object, *template_path)
                context = rendering_context_for(object)
                template_path += [context.rendering_binding]
                render_template(*template_path)
            end

            # Base class for rendering contexts
            class RenderingContext
                # Mapped object
                def initialize(object)
                    @object = object
                end

                # No links by default
                def link_to(arg)
                    if arg.respond_to?(:name)
                        arg.name
                    else arg.to_s
                    end
                end

                # Create an item for the rendering in tables
                def render_item(name, value = nil)
                    if value
                        "<li><b>#{name}</b>: #{value}</li>"
                    else
                        "<li><b>#{name}</b></li>"
                    end
                end

                def rendering_binding
                    binding
                end
            end

            class TaskRenderingContext < RenderingContext
                def initialize(task)
                    super
                end
                def task; @object end
            end
        end
    end
end
