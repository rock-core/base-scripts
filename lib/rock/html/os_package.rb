module Rock
    module HTML
        # Representation of osdeps packages within the HTML generation code.
        class OSPackage
            # The package name
            attr_reader :name
            # The osdep definition, as a list of file-to-osdep info
            attr_reader :data

            def initialize(name, data)
                @name = name
                @data = data
            end
        end
    end
end
