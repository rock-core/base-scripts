# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV['TEST_ENABLE_COVERAGE'] == '1'
    begin
        require 'simplecov'
        SimpleCov.start
    rescue LoadError
        require 'rock'
        Rock.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require 'rock'
        Rock.warn "coverage is disabled: #{e.message}"
    end
end

require 'rock'
require 'flexmock/minitest'
require 'minitest/spec'

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
    rescue Exception
        Rock.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

module Rock
    module SelfTest
        def setup
            # Setup code for all the tests
        end

        def teardown
            super
            # Teardown code for all the tests
        end
    end
end

class Minitest::Test
    include Rock::SelfTest
end

