module Rock
    module HTML
        # Representation of osdeps packages within the HTML generation code.
        class OSPackage
            # The package name
            attr_reader :name

            def initialize(name)
                @name = name
            end
        end
    end
end
