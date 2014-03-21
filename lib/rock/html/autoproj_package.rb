module Rock
    module HTML
        # Rendering object that displays information about autoproj packages
        class AutoprojPackage
            attr_reader :page, :template

            def initialize(page)
                @page = page
                @template = page.load_template(TEMPLATE_DIR, 'autoproj_package.page')
            end

            def render(object)
                page.push nil, template.result(binding)
            end

            def api_url(pkg)
                if page.respond_to?(:api_url) && (url = page.api_url(pkg))
                    url
                else
                    if pkg.description
                        REXML::XPath.each(pkg.description.xml, "//api").first
                    end
                end
            end

            def render_vcs(vcs)
                MetaRuby::GUI::HTML::Page.to_html_body(vcs, AutoprojVCS)
            end
        end
    end
end
