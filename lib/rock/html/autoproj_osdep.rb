module Rock
    module HTML
        class AutoprojOSDep
            attr_reader :page, :template

            def initialize(page)
                @page = page
                @template = page.load_template(TEMPLATE_DIR, 'autoproj_osdep.page')
            end

            def render(object)
                page.push nil, template.result(binding)
            end
        end
    end
end
