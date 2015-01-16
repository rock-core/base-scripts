module Rock
    module Browse
        class Page < MetaRuby::GUI::HTML::Page
            def role_from_object(object)
                case object
                when OroGen::Spec::TaskContext
                    ModelListWidget::ROLE_OROGEN_TASK
                when Autoproj::PackageDefinition
                    if File.directory?(object.autobuild.srcdir)
                        ModelListWidget::ROLE_INSTALLED_PACKAGE
                    else
                        ModelListWidget::ROLE_AVAILABLE_PACKAGE
                    end
                when Autoproj::PackageSet
                    ModelListWidget::ROLE_PACKAGE_SET
                when Rock::HTML::OSPackage
                    ModelListWidget::ROLE_OSDEPS
                when Class
                    if object <= Typelib::Type
                        ModelListWidget::ROLE_OROGEN_TYPE
                    end
                end
            end

            def uri_for(object)
                if role = role_from_object(object)
                    uri = Qt::Url.new
                    uri.setPath("rock-browse")
                    uri.addQueryItem('role', role.to_s)
                    uri.addQueryItem('name', object.name)
                    uri.toString
                end
            end
        end
    end
end
