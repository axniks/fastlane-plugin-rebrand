describe Fastlane::Actions::RebrandAction do
  describe '#run' do
    it 'should raise for missing parameters' do
      expect do
        Fastlane::Actions::RebrandAction.run(nil)
      end.to raise_error
      #   (Fastlane::UI).to receive(:message).with("The rebrand plugin is awake!")
      # expect()
      # Fastlane::Actions::RebrandAction.run(nil)
    end
  end
end
