# frozen_string_literal: true

RSpec.describe Capistrano::ASG::Rolling::LaunchTemplate do
  subject(:template) { described_class.new('lt-0a20c965061f64abc', 1) }

  before do
    stub_request(:post, /amazonaws.com/)
      .with(body: /Action=DescribeLaunchTemplateVersions/).to_return(body: File.read('spec/support/stubs/DescribeLaunchTemplateVersions.xml'))
  end

  describe '#create_version' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=CreateLaunchTemplateVersion/).to_return(body: File.read('spec/support/stubs/CreateLaunchTemplateVersion.xml'))
    end

    it 'calls the API to create a new launch template version' do
      template.create_version(image_id: 'ami-12345')
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=CreateLaunchTemplateVersion&LaunchTemplateData.ImageId=ami-12345&LaunchTemplateId=lt-0a20c965061f64abc&SourceVersion=1/).once
    end

    it 'returns an LaunchTemplate object with the new version' do
      version = template.create_version(image_id: 'ami-12345')
      expect(version.id).to eq('lt-0a20c965061f6454a')
      expect(version.version).to eq('4')
    end
  end

  describe '#delete' do
    before do
      stub_request(:post, /amazonaws.com/)
        .with(body: /Action=DeleteLaunchTemplateVersions/).to_return(body: File.read('spec/support/stubs/DeleteLaunchTemplateVersions.xml'))
    end

    it 'calls the API to delete this launch template version' do
      template.delete
      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=DeleteLaunchTemplateVersions&LaunchTemplateId=lt-0a20c965061f64abc&LaunchTemplateVersion.1=1/).once
    end
  end

  describe '#ami' do
    it 'returns an AMI object with image ID' do
      ami = template.ami
      expect(ami).to be_a(Capistrano::ASG::Rolling::AMI)
      expect(ami.id).to eq('ami-8c1be5f6')
    end
  end

  describe '#previous_versions' do
    it 'calls the API to retrieve the launch template versions' do
      template.previous_versions

      expect(WebMock).to have_requested(:post, /amazonaws.com/)
        .with(body: /Action=DescribeLaunchTemplateVersions&LaunchTemplateId=lt-0a20c965061f64abc/).twice
    end

    context 'when this is the first version' do
      it 'returns an empty Array' do
        versions = template.previous_versions
        expect(versions).to be_empty
      end
    end

    context 'when this is the third version' do
      subject(:template) { described_class.new('lt-0a20c965061f64abc', 3) }

      before do
        stub_request(:post, /amazonaws.com/)
          .with(body: /Action=DescribeLaunchTemplateVersions&LaunchTemplateId=lt-0a20c965061f64abc&LaunchTemplateVersion.1=3/).to_return(body: File.read('spec/support/stubs/DescribeLaunchTemplateVersions.Single.xml'))
      end

      it 'returns an Array with LaunchTemplate objects' do
        versions = template.previous_versions
        expect(versions).not_to be_empty
        expect(versions.count).to eq(2)
      end
    end
  end

  describe '#version_number' do
    it 'returns the version as number' do
      expect(template.version_number).to eq(1)
    end
  end

  describe '#image_id' do
    it 'returns the image ID from the launch template' do
      expect(template.image_id).to eq('ami-8c1be5f6')
    end
  end

  describe '#network_interfaces' do
    it 'returns the network interfaces from the launch template' do
      expect(template.network_interfaces).to be_empty
    end
  end

  describe '#security_group_ids' do
    it 'returns the security group ids from the launch template' do
      expect(template.security_group_ids).to eq(['sg-e4076980'])
    end
  end

  describe 'object equality' do
    let(:template2) { described_class.new('lt-0a20c965061f64abc', 1) }
    let(:template3) { described_class.new('lt-0a20c965061f64def', 1) }

    it 'is equal for two templates with same ID' do
      expect(template).to eql(template2)
      expect(template).to eq(template2)
    end

    it 'is not equal for two templates with different ID' do
      expect(template).not_to eql(template3)
      expect(template).not_to eq(template3)
    end

    it 'can be used in Sets without duplicates' do
      set = Set[template, template2, template3]
      expect(set.count).to eq(2)
    end
  end
end
