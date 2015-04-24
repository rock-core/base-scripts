require 'rock/test'
require 'rock/bundles'

module Rock
    describe Bundles do
        describe "discover_dependencies" do
            it "sorts dependencies topologically" do
                all_bundles =
                    [bundle0 = Bundles::Bundle.new('/path/bundle0'),
                     bundle1 = Bundles::Bundle.new('/path/bundle1'),
                     bundle2 = Bundles::Bundle.new('/path/bundle2')]
                bundle0.config = Hash['dependencies' => %w{}]
                bundle1.config = Hash['dependencies' => %w{bundle0}]
                bundle2.config = Hash['dependencies' => %w{bundle0 bundle1}]

                flexmock(Bundles).should_receive(:each_bundle).and_return(all_bundles)
                assert_equal all_bundles.reverse, Bundles.discover_dependencies(bundle2)
            end
        end
    end
end

