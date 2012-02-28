require 'erb'
module Rock
    module Doc
        OSPackage = Struct.new :name
        VizkitWidget = Struct.new :name
        class Vizkit3DWidget < VizkitWidget
        end

        module HTML
            TEMPLATE_DIR = File.expand_path(File.join('templates', 'html'), File.dirname(__FILE__))

            class << self
                attr_reader :templates
            end
            @templates = Hash.new

            def self.escape_html(string)
                string.
                    gsub('<', '&lt;').
                    gsub('>', '&gt;')
            end

            def self.obscure_email(email)
                return nil if email.nil? #Don't bother if the parameter is nil.
                lower = ('a'..'z').to_a
                upper = ('A'..'Z').to_a
                email.split('').map { |char|
                    output = lower.index(char) + 97 if lower.include?(char)
                    output = upper.index(char) + 65 if upper.include?(char)
                    output ? "&##{output};" : (char == '@' ? '&#0064;' : char)
                }.join
            end

            @help_id = 0
            def self.allocate_help_id
                @help_id += 1
            end

            def self.help_tip(doc)
                id = allocate_help_id
                "<span class=\"help_trigger\" id=\"#{id}\"><img src=\"{relocatable: /img/help.png}\" /></span><div class=\"help\" id=\"help_#{id}\">#{doc}</div>"
            end

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
                when Autoproj::PackageDefinition
                    PackageRenderingContext.new(object)
                when Autoproj::VCSDefinition
                    VCSRenderingContext.new(object)
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
                if template_path.last.kind_of?(Hash)
                    options = template_path.pop
                else
                    options = Hash.new
                end
                options = Kernel.validate_options options,
                    :context => nil

                context = options[:context] || rendering_context_for(object)
                if template_path.empty?
                    template_path = context.default_template
                    if !template_path || template_path.empty?
                        raise ArgumentError, "no default fragment defined for #{object}, of class #{object.class}"
                    end
                end

                context.render(*template_path)
            end

            # Base class for rendering contexts
            class RenderingContext
                attr_reader :object
                attr_reader :default_template

                # Mapped object
                def initialize(object, *default_template)
                    @object = object
                    @default_template = default_template
                end

                # No links by default
                def link_to(arg)
                    text =
                        if arg.respond_to?(:name)
                            arg.name
                        else arg.to_s
                        end

                    Doc::HTML.escape_html(text)
                end

                # No help tips by default, it relies on having specialized
                # mechanisms too much
                def help_tip(text); "" end

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

                def render_object(object, *template_path)
                    HTML.render_object(object, *template_path)
                end
            end

            class PackageRenderingContext < RenderingContext
                def has_api?(pkg)
                    false
                end
                def api_link(pkg, text)
                    nil
                end
            end

            class TaskRenderingContext < RenderingContext
                def task; @object end
                def initialize(object)
                    super(object, 'orogen_task_fragment.page')
                end
            end

            class TypeRenderingContext < RenderingContext
                def type; @object end

                attr_reader :intermediate_type
                attr_reader :ruby_type
                attr_reader :produced_by
                attr_reader :consumed_by
                attr_reader :displayed_by

                def initialize(object)
                    super(object, 'orogen_type_fragment.page')
                    @produced_by = []
                    @consumed_by = []
                    @displayed_by = []
                end

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

            class VCSRenderingContext < RenderingContext
                def vcs; object end

                def initialize(object)
                    super(object, 'autoproj_vcs_fragment.page')
                end

                def render(*template_path)
                    if vcs.raw
                        first = true
                        raw_info = vcs.raw.map do |pkg_set, vcs_info|
                            fragment = super
                            if !first
                                fragment = "<span class=\"vcs_override\">overriden in #{pkg_set}</span>" + fragment
                            end
                            first = false
                            fragment
                        end
                        raw_vcs = "<div class=\"vcs\">Rock short definition<span class=\"toggle\">show/hide</span><div class=\"vcs_info\">#{raw_info.join("\n")}</div></div>"
                    end

                    vcs_info = self.vcs
                    raw_vcs +
    "<div class=\"vcs\">Autoproj definition<span class=\"toggle\">show/hide</span><div class=\"vcs_info\">#{super}</div></div>"
                end
            end
        end
    end
end
