module Rock
    module HTML
        # Rendering object that displays information about autoproj version
        # control information
        class AutoprojVCS
            attr_reader :page, :template

            def initialize(page)
                @page = page
                @template = page.load_template(TEMPLATE_DIR, 'autoproj_vcs.page')
            end

            def render(vcs, options = Hash.new)
                page.push nil, template.result(binding)
            end
        end
    end
end

