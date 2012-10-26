module Hydra::Controller::DatastreamsBehavior
  extend ActiveSupport::Concern
  
  included do
    include Hydra::AccessControlsEnforcement
    include Hydra::AssetsControllerHelper
    include Hydra::Controller::UploadBehavior 
    include Hydra::Controller::RepositoryControllerBehavior
    include Blacklight::SolrHelper
    include Blacklight::Configurable
    copy_blacklight_config_from(CatalogController)
    prepend_before_filter :sanitize_update_params
  end
  
  def fedora_object_not_found
    flash[:notice] = "No object exists for #{params.delete(:asset_id)}"
    @container = nil
    @datastreams = {}
    render :controller=>'catalog', :action=>:index, :status=>404
  end
  
  def datastream_not_found
    flash[:notice] = "No #{params.delete(:id)} datastream exists for #{params.delete(:asset_id)}"
    render :partial=>:index, :status=>404
  end
  
  def container
    @container ||= begin
      if params[:asset_id].nil?
        nil
      else
        @permissions_solr_response, @permissions_solr_document = get_permissions_solr_response_for_doc_id(params[:asset_id])
        ActiveFedora::Base.find(params[:asset_id])
      end
    end
  end

  def datastream
    @datastream ||= begin
      if params[:id].nil?
        nil
      else
        container.datastreams[params[:id]]
      end
    end
  end

  def index
    if container.nil?
      fedora_object_not_found
      return
    end
    if can? :read, @permissions_solr_document
      if params[:layout] == "false"
        layout = false
      end
      unless params[:asset_id].nil?
        # Including this line so permissions tests can be run against the container
        @container_response, @document = get_solr_response_for_doc_id(params[:asset_id])
        # It would be nice to handle these in a callback (before_render :yyy)
        @container =  ActiveFedora::Base.find(params[:asset_id])
        @datastreams = @container.inner_object.datastreams.values
        if params[:id].nil? or @container.datastreams.include?(params[:id])
          render :partial=>"index", :layout=>layout, :locals => { :datastreams => @datastreams }
        else # we got here from a failed show action
          render :partial=>"index", :layout=>layout, :locals => { :datastreams => @datastreams }, :status=>404
        end
      else
        # What are we doing here without a containing object?
        flash[:notice] = "called DatastreamsController#index without containing object"
        @container = nil
        @datastreams = {}
        render :partial=>"index", :layout=>layout, :status=>404
      end
    else
      raise Hydra::AccessDenied.new("You do not have sufficient access privileges to #{params[:action]} datastreams for this object.")
    end
  end
  
  def new
    render :partial=>"new", :layout=>false
  end
  
  # Creates and Saves a Datastream to contain the the Uploaded file 
  def create
    if container.nil?
      fedora_object_not_found
      return
    end

    if can? :edit, @permissions_solr_document
      @datastream = @container.create_datastream(ActiveFedora::Datastream, params[:id])
      @container.add_datastream(@datastream)
      add_or_update
    else
      raise Hydra::AccessDenied.new("You do not have sufficient access privileges to #{params[:action]} datastreams for this object.")
    end
  end

  def ds_opts_from_params
    opts = {}
    opts[:dsLabel] = ds_filename_from_params
    opts[:dsState] = params[:ds_state] if params[:ds_state]
    opts[:formatUri] = params[:format_uri]  if params[:format_uri]
    opts[:versionable] = boolean_value(params[:versionable])  if params[:versionable]   
    opts[:checksumType] = params[:checksum_type]  if params[:checksum_type]    
    opts[:checksum] = params[:checksum]  if params[:checksum]    
    opts[:logMessage] = params[:log_message]  if params[:log_message]    
    if params.has_key?(:Filedata)
      opts[:controlGroup] = 'M'
      opts[:content] = posted_file
    elsif params.has_key?(:content)
      opts[:controlGroup] = 'M'
      opts[:content] = params[:content]
    elsif params.has_key?(:Urldata)
      control_group = params.fetch(:control_group,'M')
      control_group = 'M' if control_group.empty?
      control_group = control_group.first if control_group.is_a? Array
      opts[:controlGroup] = control_group
      opts[:dsLocation] = params[:Urldata]
      opts[:content] = nil
    end
    if opts[:dsLabel]
      opts[:mimeType] = params[:mime_type] || mime_type(opts[:dsLabel])
    end
    opts
  end

  # parse as boolean
  def boolean_value(src)
    return true if src == true || src == 1 || src =~ /^(t|true|y|yes|1)$/i
    return false if src == false || src == 0 || src.empty? || src =~ /^(f|false|n|no|0)$/i      
    logger.warn "Unexpected argument for boolean_value: #{src.to_s}"
    return false
  end
    
  def add_or_update
    opts = ds_opts_from_params
    opts.delete(:controlGroup) unless @datastream.new?

    # the code below can work around hydra-861 if necessary until fixed
    #ds_props = {:pid=>@container.pid,:dsid=>params[:id]}.merge(opts)
    #repo = ActiveFedora::Base.connection_for_pid(params[:asset_id])
    #repo.add_datastream(ds_props)

    opts.each do |key, value|
      @datastream.send :"#{key}=", value
    end
    @datastream.save
    if params.has_key?(:Filedata)
      flash[:notice] = "The file #{params[:Filename]} has been saved as #{params[:id]} in <a href=\"#{hydra_asset_url(@container.pid)}\">#{@container.pid}</a>."
    elsif params.has_key?(:Urldata)
      flash[:notice] = "#{params[:Urldata]} has been saved as #{params[:id]} in <a href=\"#{hydra_asset_url(@container.pid)}\">#{@container.pid}</a>."
    elsif params.has_key?(:content)
      flash[:notice] = "Posted content has been saved as #{params[:id]} in <a href=\"#{hydra_asset_url(@container.pid)}\">#{@container.pid}</a>."
    else
      flash[:notice] = "You must specify a file to upload or a source URL."
    end

    unless params[:asset_id].nil?
      redirect_params = {:asset_id=>params[:asset_id], :action=>:index}
    end

    redirect_params ||= {:action=>:index}

    redirect_to redirect_params
  end
  
  def update
    if container.nil?
      fedora_object_not_found
      return
    end
    if can? :edit, @permissions_solr_document
      if datastream.nil?
        datastream_not_found
        return
      end
      add_or_update
    else
      raise Hydra::AccessDenied.new("You do not have sufficient access privileges to #{params[:action]} datastreams for this object.")
    end
  end

  def show
    if container.nil?
      fedora_object_not_found
      return
    else
      if can? :read, @permissions_solr_document
        unless datastream.nil?
          repo = ActiveFedora::Base.connection_for_pid(params[:pid])
          if  @datastream.controlGroup == 'M' or @datastream.controlGroup == 'X'
            set_show_headers(@datastream)
            self.response_body = Enumerator.new do |blk|
              repo.datastream_dissemination(:pid=>params[:asset_id], :dsid=>params[:id]) do |res|
                res.read_body do |chunk|
                  blk << chunk # this is synonymous with a yield
                end
              end
            end
          else
            redirect_to ds.dsLocation
          end
          return
        else
          datastream_not_found
          return
        end
      else
        raise Hydra::AccessDenied.new("You do not have sufficient access privileges to #{params[:action]} datastreams for this object.")
      end
    end
  end

  # can't override a method defined in the module included on include
  def ds_filename_from_params
    if params.has_key? :Filedata or params.has_key? :Filename
      filename_from_params
    elsif params.has_key? :Urldata
      url = URI.parse(params[:Urldata])
      return url.path.split('/')[-1]
    end
    return nil
  end

  def set_show_headers(ds)
    mime_type = (params[:mime_type].nil?) ? ds.mimeType : params[:mime_type]
    disposition = (params[:disposition].nil?) ? "attachment" : params[:disposition]
    headers['Content-Type'] = mime_type
    headers['Content-Disposition'] = "#{disposition}; filename=\"#{ds.label}\""
    if (ds.dsSize and ds.dsSize > 0)
      headers['Content-Length'] = ds.dsSize.to_s
    else
      headers['Transfer-Encoding'] = 'chunked'
    end
    headers['Last-Modified'] = ds.lastModifiedDate || Time.now.ctime.to_s
  end
  
  def destroy
    if container.nil?
      fedora_object_not_found
      return
    end
    if can? :edit, @permissions_solr_document
      @container.datastreams[params[:id]].delete
      @datastreams = @container.inner_object.datastreams.values
      render :text => "Deleted #{params[:id]} from #{params[:asset_id]}."
    else
      raise Hydra::AccessDenied.new("You do not have sufficient access privileges to #{params[:action]} datastreams for this object.")
    end
  end  
end