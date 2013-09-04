require 'rock'

module Rock
    module HTML
        include Logger::Hierarchy

        TEMPLATE_DIR = File.expand_path('html', File.dirname(__FILE__))

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
    end
end

require 'rock/html/autoproj_package'
require 'rock/html/autoproj_vcs'
require 'rock/html/os_package'
require 'rock/html/autoproj_package_set'
require 'rock/html/autoproj_osdep'
