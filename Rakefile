require 'rake'

begin
    require 'hoe'
    Hoe::plugin :yard

    Hoe::RUBY_FLAGS.gsub! /-w/, ''

    hoe_spec = Hoe.spec 'scripts' do
        developer 'Sylvain Joyeux', 'sylvain.joyeux@m4x.org'
        self.version = 0.1
        self.description = 'Scripts that are generally useful in a Rock installation'
        self.urls        = ["https://github.com/rock-core/base-scripts"]
        self.readme_file = FileList['README*'].first
        self.history_file = "History.txt"
        licenses << 'GPLv2+'

        extra_deps <<
            ['kramdown'] <<
            ['hoe'] <<
            ['hoe-yard'] <<
            ['thor'] <<
            ['rake']

        test_globs = ['test/**_test.rb']
    end

    Rake.clear_tasks(/^default$/)
    task :default => []
    task :docs => :yard
    task :redocs => :yard
rescue LoadError
    STDERR.puts "cannot load the Hoe gem. Distribution is disabled"
rescue Exception => e
    if e.message !~ /\.rubyforge/
        STDERR.puts "WARN: cannot load the Hoe gem, or Hoe fails. Publishing tasks are disabled"
        STDERR.puts "WARN: error message is: #{e.message}"
    end
end
