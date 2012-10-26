require 'spec_helper'

describe Hydra::Controller::DatastreamsBehavior do

  before :all do
    class MockController < ApplicationController
      include Hydra::Controller::DatastreamsBehavior
      attr_accessor :params
      
      def can?(action, opts)
        true
      end

      def render(*args)
      end

      def redirect_to(*args)
      end

      def headers
        @headers ||= {}
      end

      def flash
        @flash ||= {}
      end
    end
  end

  subject { MockController.new}
  
  it "should use DatastreamsController" do
    subject.is_a?(Hydra::Controller::DatastreamsBehavior).should be_true
  end

  def assigned(sym)
    subject.instance_variable_get(:"@#{sym.to_s}")
  end
    
  describe "index" do
    
    it "should find all datastreams belonging to a given object if pid is provided" do
      pid = 'hydrangea:fixture_file_asset1'
      subject.params = {:method=>:get, :action=>:index, :asset_id=>pid}
      subject.index 
      (assigned(:datastreams).map{|d| d.dsid}).sort.should == ["DC","DS1", "RELS-EXT","descMetadata"]
      
      assigned(:container_response)[:response][:docs].first["id"].should == "hydrangea:fixture_file_asset1"
      assigned(:document).id.should == "hydrangea:fixture_file_asset1"
      assigned(:container).should == ActiveFedora::Base.find('hydrangea:fixture_file_asset1')
    end
  end

  describe "show" do
    it "should get the datastream indicated by :asset_id and :id" do
      pid = 'hydrangea:fixture_file_asset1'
      dsid = 'descMetadata'
      subject.params = {:method=>:get, :action=>:show, :asset_id=>pid, :id=>dsid}
      subject.show 
      assigned(:datastream).pid.should == pid
      assigned(:datastream).dsid.should == dsid
      assigned(:datastream).new?.should == false
    end
  end

  describe "new" do
  end

  describe "create" do
    it "should create a new datastream" do
      pid = 'hydrangea:fixture_file_asset1'
      dsid = "DSID"
      subject.params = {:method=>:post, :action=>:create, :asset_id=>pid, :id=>dsid}
      subject.create 
      assigned(:datastream).pid.should == pid
      assigned(:datastream).dsid.should == dsid
      assigned(:datastream).new?.should == true
    end
  end

  describe "update" do
    it "should set properties on an exisiting datastream" do
      pid = 'hydrangea:fixture_file_asset1'
      dsid = 'descMetadata'
      msg = 'TEST MESSAGE'
      subject.params = {:method=>:put, :action=>:update, :asset_id=>pid, :id=>dsid, :log_message=>msg}
      subject.create 
      assigned(:datastream).pid.should == pid
      assigned(:datastream).dsid.should == dsid
      assigned(:datastream).new?.should == false
      assigned(:datastream).logMessage.should == msg
    end
  end

  describe "destroy" do
    it "should delete the datastream identified by asset_id and id" do
      mock_obj = double("asset")
      mock_ds = double("ds")
      mock_inner = double("inner_object")
      mock_obj.should_receive(:inner_object).and_return(mock_inner)
      mock_obj.should_receive(:datastreams).and_return({"DS1"=>mock_ds})
      mock_inner.should_receive(:datastreams).and_return({})
      mock_ds.should_receive(:delete)
      pid = 'hydrangea:fixture_file_asset1'
      ActiveFedora::Base.should_receive(:find).with(pid).and_return(mock_obj)
      subject.params = {:method=>:delete,:action=>:destroy,:asset_id => pid, :id=>"DS1"}
      subject.destroy
    end
  end
end

describe Hydra::DatastreamsController do
  include Devise::TestHelpers

  it "should be restful" do
    { :get => "/hydra/assets/hydrangea:fixture_file_asset1/datastreams" }.should route_to(:controller=>'hydra/datastreams', :action=>'index', :asset_id=>"hydrangea:fixture_file_asset1")
    { :get=> "/hydra/assets/hydrangea:fixture_file_asset1/datastreams/DS1" }.should route_to(:controller=>'hydra/datastreams', :action=>'show', :asset_id=>"hydrangea:fixture_file_asset1", :id=>'DS1')
    { :put=>"/hydra/assets/hydrangea:fixture_file_asset1/datastreams/DS1" }.should route_to(:controller=>'hydra/datastreams', :action=>'update', :asset_id=>"hydrangea:fixture_file_asset1", :id=>'DS1')
    { :post => "/hydra/assets/hydrangea:fixture_file_asset1/datastreams" }.should route_to(:controller=>'hydra/datastreams', :action=>'create', :asset_id=>"hydrangea:fixture_file_asset1")
    { :delete=> "/hydra/assets/hydrangea:fixture_file_asset1/datastreams/DS1" }.should route_to(:controller=>'hydra/datastreams', :action=>'destroy', :asset_id=>"hydrangea:fixture_file_asset1", :id=>'DS1')
  end

  describe "integration tests - " do
    def mock_user
      Devise.stub(:authentication_keys =>[:email])
      mock_user = double("User")
      mock_user.stub(:email).and_return('user@example.com')
      mock_user.stub(:user_key).and_return('email')
      mock_user.stub(:"new_record?").and_return(false)
      mock_user.stub(:"persisted?").and_return(true)
      controller.stub(:current_user).and_return(mock_user)
    end

    before(:all) do
      class TestObj < ActiveFedora::Base
        include ActiveFedora::Datastreams
        include Hydra::ModelMixins::RightsMetadata
        has_file_datastream :name=>'content'
        has_metadata :name=>'rightsMetadata', :type=>Hydra::Datastream::RightsMetadata
      end
      ActiveFedora::SolrService.register(ActiveFedora.solr_config[:url])
    end

    before(:each) do
      @test_container = TestObj.new
      @test_container.content.content = "<foo>bar</foo>"
      @test_container.edit_users=['user@example.com']
      @test_container.read_groups=['public']
      @test_container.save
    end

    after(:each) do
     @test_container.delete
    end

    after(:all) do
     Object.send(:remove_const, :TestObj)
    end

    describe "index" do
      it "should retrieve the container object's datastreams" do
        get :index, {:asset_id=>@test_container.pid}
        @controller.params[:asset_id].should_not be_nil
        (@controller.instance_variable_get(:@datastreams).map {|d| d.dsid }).sort.should == ['DC','RELS-EXT','content','rightsMetadata']
      end
    end

    describe "create" do
      describe "with session" do
        before :each do
          mock_user
        end

        it "should create new datastreams" do
          content = '<bar>baz</bar>'
          post :create, {:asset_id=>@test_container.pid, :id=>'bar',:content=>content, :Filename=>'bar.xml'}
          test = TestObj.find(@test_container.pid)
          test.datastreams.should include('bar')
          test.datastreams['bar'].content.should == content
        end

      end

      describe "without session" do
        it "should fail to create new datastreams" do
          content = '<bar>baz</bar>'
          post :create, {:asset_id=>@test_container.pid, :id=>'bar',:content=>content, :Filename=>'bar.xml'}
          TestObj.find(@test_container.pid).datastreams.should_not include('bar')
        end
      end
    end

    describe "update" do
      describe "with session" do
        before :each do
          mock_user
        end
      end
      describe "without session" do
        it "should fail to update datastreams" do
        end
      end
    end

    describe "delete" do
      describe "with session" do
        before :each do
          mock_user
        end

        it "should delete datastreams" do
          delete :destroy, {:asset_id=>@test_container.pid,:id=>'content'}
          TestObj.find(@test_container.pid).datastreams['content'].new?.should be_true
          (assigns[:datastreams].map {|d| d.dsid }).sort.should == ['DC','RELS-EXT','rightsMetadata']
        end
      end
      describe "without session" do
        it "should fail to delete datastreams" do
          begin
            delete :destroy, {:asset_id=>@test_container.pid,:id=>'content'}
          rescue
          end
          TestObj.find(@test_container.pid).datastreams.should include('content')
        end
      end
    end

  end

end
