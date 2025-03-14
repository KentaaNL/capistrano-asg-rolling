# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::LaunchTemplates do
  subject(:templates) { described_class.new }

  let(:template1) { Capistrano::ASG::Rolling::LaunchTemplate.new('lt-0a20c965061f64abc', 1, 'MyLaunchTemplate') }

  before do
    templates << template1
  end

  describe '#<<' do
    it 'adds a launch template to the set' do
      templates << Capistrano::ASG::Rolling::LaunchTemplate.new('lt-0a20c965061f6454a', 1, 'MyLaunchTemplate')
      expect(templates.count).to eq(2)
    end

    it 'does not allow duplicate launch templates' do
      templates << template1
      expect(templates.count).to eq(1)
    end
  end

  describe '#merge' do
    let(:templates2) { described_class.new }

    before do
      templates2 << template1
      templates2 << Capistrano::ASG::Rolling::LaunchTemplate.new('lt-0a20c965061f6454a', 1, 'MyLaunchTemplate')
    end

    it 'merges the two template sets' do
      templates.merge(templates2)
      expect(templates.count).to eq(2)
    end
  end

  describe '#each' do
    it 'returns an Enumerator' do
      expect(templates.each).to be_a(Enumerator)
    end
  end

  describe '#empty?' do
    context 'when collection is not empty' do
      it 'returns false' do
        expect(templates).not_to be_empty
      end
    end

    context 'when collection is empty' do
      it 'returns true' do
        empty_templates = described_class.new
        expect(empty_templates).to be_empty
      end
    end
  end

  describe '#update' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DescribeLaunchTemplateVersions/).to_return(body: File.read('spec/support/stubs/DescribeLaunchTemplateVersions.xml'))
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=CreateLaunchTemplateVersion/).to_return(body: File.read('spec/support/stubs/CreateLaunchTemplateVersion.xml'))
    end

    let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', 'ami-8c1be5f6', nil) }
    let(:ami) { Capistrano::ASG::Rolling::AMI.new('ami-12345', instance) }

    it 'calls the API to create a new launch template version' do
      templates.update(amis: [ami])
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateLaunchTemplateVersion&ClientToken=.+&LaunchTemplateData.ImageId=ami-12345&LaunchTemplateId=lt-0a20c965061f64abc&SourceVersion=1/).once
    end

    it 'returns the updated launch template versions' do
      updated_templates = templates.update(amis: [ami])
      expect(updated_templates).to be_a(described_class)

      version = updated_templates.first
      expect(version.id).to eq('lt-0a20c965061f6454a')
      expect(version.version).to eq('4')
    end

    context 'when old AMI does not exist' do
      let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', 'ami-67890', nil) }

      it 'does not call the API' do
        templates.update(amis: [ami])
        expect(WebMock).not_to have_requested(:post, /amazonaws.com/).with(body: /Action=CreateLaunchTemplateVersion/)
      end
    end

    context 'when Instance has no AMI' do
      let(:instance) { Capistrano::ASG::Rolling::Instance.new('i-12345', '192.168.1.88', '54.194.252.215', nil, nil) }

      it 'does not call the API' do
        templates.update(amis: [ami])
        expect(WebMock).not_to have_requested(:post, /amazonaws.com/).with(body: /Action=CreateLaunchTemplateVersion/)
      end
    end
  end
end
