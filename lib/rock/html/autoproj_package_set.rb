module Rock
    module HTML
        class AutoprojPackageSet
            attr_reader :page, :template

            def initialize(page)
                @page = page
                @template = page.load_template(TEMPLATE_DIR, 'autoproj_package_set.page')
            end

            def render(info, pkg_set)
                page.push nil, template.result(binding)
            end

            def render_vcs(vcs)
                MetaRuby::GUI::HTML::Page.to_html_body(vcs, AutoprojVCS)
            end
        end
    end
end

