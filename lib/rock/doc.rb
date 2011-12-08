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

            def self.render_page(body)
                html =<<-EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en">
<head>
    <link rel="stylesheet" href="file://#{File.join(Rock::Doc::HTML.template_path, "style.css")}" type="text/css" />
</head>
<body>
     #{body}
</body>
                EOF
            end

            def self.rendering_context_for(object)
                case object
                when Orocos::Spec::TaskContext
                    TaskRenderingContext.new(object)
                when Class
                    if object <= Typelib::Type
                        TypeRenderingContext.new(object)
                    else
                        RenderingContext.new(object)
                    end
                else
                    RenderingContext.new(object)
                end
            end

            def self.render_object(object, *template_path)
                context = rendering_context_for(object)
                context.render(*template_path)
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

                def render(*template_path)
                    template_path += [binding]
                    HTML.render_template(*template_path)
                end
            end

            class TaskRenderingContext < RenderingContext
                def task; @object end
            end

            class TypeRenderingContext < RenderingContext
                def type; @object end

                attr_reader :intermediate_type
                attr_reader :ruby_type

                def has_convertions?(type, recursive = true)
                    if type <= Typelib::NumericType
                        return false
                    elsif type.convertion_to_ruby
                        return true
                    end
                    return if !recursive

                    if type < Typelib::CompoundType
                        type.enum_for(:each_field).any? do |field_name, field_type|
                            has_convertions?(field_type, false)
                        end
                    elsif type < Typelib::EnumType
                        false
                    elsif type.respond_to?(:deference)
                        return has_convertions?(type.deference, false)
                    else
                        raise NotImplementedError
                    end
                end

                def render_convertion_spec(base_type, convertion)
                    if spec = convertion[0]
                        if spec == Array
                            # The base type is most likely an array or a container.
                            # Display the element type as well ...
                            if base_type.respond_to?(:deference)
                                if subconv = base_type.deference.convertion_to_ruby
                                    return "Array(#{render_convertion_spec(base_type.deference, subconv)})"
                                else
                                    return "Array(#{link_to(base_type.deference)})"
                                end
                            end
                        end
                        convertion[0].name

                    else
                        "converted to an unspecified type"
                    end
                end

                def render_type_convertion(type)
                    result = []
                    if convertion = type.convertion_to_ruby
                        result << render_convertion_spec(type, convertion)
                    elsif type < Typelib::CompoundType
                        result << "<ul class=\"body-header-list\">"
                        type.each_field do |field_name, field_type|
                            if convertion = field_type.convertion_to_ruby
                                result << render_item(field_name, render_convertion_spec(field_type, convertion))
                            else
                                result << render_item(field_name, link_to(field_type))
                            end
                        end
                        result << "</ul>"
                    elsif type < Typelib::ArrayType
                        result << "<ul class=\"body-header-list\">"
                        deference =
                            if convertion = type.deference.convertion_to_ruby
                                render_convertion_spec(type.deference, convertion)
                            else
                                render_convertion_spec(type.deference, [Array])
                            end
                        result << "<li>#{deference}[#{type.length}]</li>"
                        result << "</ul>"
                    elsif type < Typelib::ContainerType
                        result << "<ul class=\"body-header-list\">"
                        deference =
                            if convertion = type.deference.convertion_to_ruby
                                render_convertion_spec(type.deference, convertion)
                            else
                                link_to(type.deference)
                            end
                        result << "<li>Array(#{deference})</li>"
                        result << "</ul>"
                    else
                        raise NotImplementedError
                    end
                    result.join("\n")
                end

                def render_type_definition_fragment(type)
                    HTML.render_template("type_definition_fragment.page", binding)
                end

                def render(*template_path)
                    base = self.type
                    typekit = Orocos.load_typekit_for(base, false)

                    if base.contains_opaques?
                        @intermediate_type = typekit.intermediate_type_for(type)
                        if has_convertions?(intermediate_type)
                            @ruby_type = intermediate_type
                        end
                    elsif has_convertions?(base)
                        @ruby_type = base
                    end

                    super
                end
            end
        end
    end
end
