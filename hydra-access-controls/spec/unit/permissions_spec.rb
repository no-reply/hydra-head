require 'spec_helper'

describe Hydra::AccessControls::Permissions do
  before do
    class Foo < ActiveFedora::Base
      include Hydra::AccessControls::Permissions
    end
  end

  subject { Foo.new }

  
  it "should have a set of permissions" do
    subject.read_groups=['group1', 'group2']
    subject.edit_users=['user1']
    subject.read_users=['user2', 'user3']
    subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"group", :access=>"read", :name=>"group1"),
        Hydra::AccessControls::Permission.new({:type=>"group", :access=>"read", :name=>"group2"}),
        Hydra::AccessControls::Permission.new({:type=>"user", :access=>"read", :name=>"user2"}),
        Hydra::AccessControls::Permission.new({:type=>"user", :access=>"read", :name=>"user3"}),
        Hydra::AccessControls::Permission.new({:type=>"user", :access=>"edit", :name=>"user1"})]
  end
  describe "updating permissions" do
    before do
      subject.permissions_attributes = [{:type=>"user", :access=>"edit", :name=>"jcoyne"}]
    end
    it "should handle a hash" do
      subject.permissions_attributes = {'0' => {type: "group", access:"read", name:"group1"}, '1'=> {type: 'user', access: 'edit', name: 'user2'}}
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"group", :access=>"read", :name=>"group1"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"user2")]
    end
    it "should create new group permissions" do
      subject.permissions_attributes = [{:type=>"group", :access=>"read", :name=>"group1"}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"group", :access=>"read", :name=>"group1"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should create new user permissions" do
      subject.permissions_attributes = [{:type=>"user", :access=>"read", :name=>"user1"}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"user", :access=>"read", :name=>"user1"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should not replace existing groups" do
      subject.permissions_attributes = [{:type=>"group", :access=>"read", :name=>"group1"}]
      subject.permissions_attributes = [{:type=>"group", :access=>"read", :name=>"group2"}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"group", :access=>"read", :name=>"group1"),
                                   Hydra::AccessControls::Permission.new(:type=>"group", :access=>"read", :name=>"group2"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should not replace existing users" do
      subject.permissions_attributes = [{:type=>"user", :access=>"read", :name=>"user1"}]
      subject.permissions_attributes = [{:type=>"user", :access=>"read", :name=>"user2"}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"user", :access=>"read", :name=>"user1"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"read", :name=>"user2"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should update permissions on existing users" do
      subject.permissions_attributes = [{:type=>"user", :access=>"read", :name=>"user1"}]
      subject.permissions_attributes = [{:type=>"user", :access=>"edit", :name=>"user1"}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"user1"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should update permissions on existing groups" do
      subject.permissions_attributes = [{:type=>"group", :access=>"read", :name=>"group1"}]
      subject.permissions_attributes = [{:type=>"group", :access=>"edit", :name=>"group1"}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"group", :access=>"edit", :name=>"group1"),
                                   Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should remove permissions on existing users" do
      subject.permissions_attributes = [{:type=>"user", :access=>"read", :name=>"user1"}]
      subject.permissions_attributes = [{:type=>"user", :access=>"edit", :name=>"user1", _destroy: true}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should remove permissions on existing groups" do
      subject.permissions_attributes = [{:type=>"group", :access=>"read", :name=>"group1"}]
      subject.permissions_attributes = [{:type=>"group", :access=>"edit", :name=>"group1", _destroy: '1'}]
      subject.permissions.should == [Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
    it "should not remove when destroy flag is falsy" do
      subject.permissions_attributes = [{:type=>"group", :access=>"read", :name=>"group1"}]
      subject.permissions_attributes = [{:type=>"group", :access=>"edit", :name=>"group1", _destroy: '0'}]
      subject.permissions.should == [ Hydra::AccessControls::Permission.new(:type=>"group", :access=>"edit", :name=>"group1"),
                                      Hydra::AccessControls::Permission.new(:type=>"user", :access=>"edit", :name=>"jcoyne")]
    end
  end

  context "to_solr" do
    let(:embargo_release_date) { "2010-12-01" }
    before do
      subject.rightsMetadata.embargo_release_date = embargo_release_date
      subject.rightsMetadata.update_permissions("person"=>{"person1"=>"read","person2"=>"discover"}, "group"=>{'group-6' => 'read', "group-7"=>'read', 'group-8'=>'edit'})
    end
    it "should produce a solr document" do
      result = subject.rightsMetadata.to_solr
      result.size.should == 5
      ## Wrote the test in this way, because the implementation uses a hash, and the hash order is not deterministic (especially in ruby 1.8.7)
      result['read_access_group_ssim'].size.should == 2
      result['read_access_group_ssim'].should include('group-6', 'group-7')
      result['edit_access_group_ssim'].should == ['group-8']
      result['discover_access_person_ssim'].should == ['person2']
      result['read_access_person_ssim'].should == ['person1']
      result['embargo_release_date_dtsi'].should == subject.rightsMetadata.embargo_release_date(:format => :solr_date)
    end
  end

  context "with rightsMetadata" do
    before do
      subject.rightsMetadata.update_permissions("person"=>{"person1"=>"read","person2"=>"discover"}, "group"=>{'group-6' => 'read', "group-7"=>'read', 'group-8'=>'edit'})
    end
    it "should have read groups accessor" do
      subject.read_groups.should == ['group-6', 'group-7']
    end
    it "should have read groups string accessor" do
      subject.read_groups_string.should == 'group-6, group-7'
    end
    it "should have read groups writer" do
      subject.read_groups = ['group-2', 'group-3']
      subject.rightsMetadata.groups.should == {'group-2' => 'read', 'group-3'=>'read', 'group-8' => 'edit'}
      subject.rightsMetadata.users.should == {"person1"=>"read","person2"=>"discover"}
    end

    it "should have read groups string writer" do
      subject.read_groups_string = 'umg/up.dlt.staff, group-3'
      subject.rightsMetadata.groups.should == {'umg/up.dlt.staff' => 'read', 'group-3'=>'read', 'group-8' => 'edit'}
      subject.rightsMetadata.users.should == {"person1"=>"read","person2"=>"discover"}
    end
    it "should only revoke eligible groups" do
      subject.set_read_groups(['group-2', 'group-3'], ['group-6'])
      # 'group-7' is not eligible to be revoked
      subject.rightsMetadata.groups.should == {'group-2' => 'read', 'group-3'=>'read', 'group-7' => 'read', 'group-8' => 'edit'}
      subject.rightsMetadata.users.should == {"person1"=>"read","person2"=>"discover"}
    end
  end
end
