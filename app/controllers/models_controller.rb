require "fileutils"

class ModelsController < ApplicationController
  include ModelListable
  include Permittable

  rate_limit to: 10, within: 3.minutes, only: :create

  before_action :redirect_search, only: [:index], if: -> { params.key?(:q) }
  before_action :get_model, except: [:bulk_edit, :bulk_update, :index, :new, :create]
  before_action :get_creators_and_collections, only: [:new, :edit, :bulk_edit]
  before_action :set_returnable, only: [:bulk_edit, :edit, :new]
  before_action :clear_returnable, only: [:bulk_update, :update, :create]
  before_action :get_filters, only: [:bulk_edit, :bulk_update, :index, :show] # rubocop:todo Rails/LexicallyScopedActionFilter

  after_action :verify_policy_scoped, only: [:bulk_edit, :bulk_update]

  def index
    @models = filtered_models @filters
    prepare_model_list
    respond_to do |format|
      format.html { render layout: "card_list_page" }
      format.manyfold_api_v0 { render json: ManyfoldApi::V0::ModelListSerializer.new(@models).serialize }
    end
  end

  def show
    respond_to do |format|
      format.html do
        files = policy_scope(@model.model_files).without_special
        @locked_files = @model.model_files.without_special.count - files.count
        @images = files.select(&:is_image?)
        @images.unshift(@model.preview_file) if @images.delete(@model.preview_file)
        if helpers.file_list_settings["hide_presupported_versions"]
          hidden_ids = files.select(:presupported_version_id).where.not(presupported_version_id: nil)
          files = files.where.not(id: hidden_ids)
        end
        files = files.includes(:presupported_version, :problems)
        files = files.reject(&:is_image?)
        @groups = helpers.group(files)
        @num_files = files.count
        render layout: "card_list_page"
      end
      format.zip do
        download = ArchiveDownloadService.new(model: @model, selection: params[:selection])
        if download.ready?
          send_file(download.output_file, filename: download.filename, type: :zip, disposition: :attachment)
        elsif download.preparing?
          redirect_to model_path(@model, format: :html), notice: t(".download_preparing")
        else
          download.prepare
          redirect_to model_path(@model, format: :html), notice: t(".download_requested")
        end
      end
      format.oembed { render json: OEmbed::ModelSerializer.new(@model, helpers.oembed_params).serialize }
      format.manyfold_api_v0 { render json: ManyfoldApi::V0::ModelSerializer.new(@model).serialize }
    end
  end

  def new
    authorize :model
    generate_available_tag_list
  end

  def edit
    @model.links.build if @model.links.empty? # populate empty link
    @model.caber_relations.build if @model.caber_relations.empty?
    generate_available_tag_list
  end

  def create
    authorize :model
    library = SiteSettings.show_libraries ? Library.find_param(params[:library]) : Library.default
    uploads = begin
      JSON.parse(params[:uploads])
    rescue
      []
    end

    uploads.each do |upload|
      ProcessUploadedFileJob.perform_later(
        library.id,
        upload,
        owner: current_user,
        creator_id: params[:creator_id],
        collection_id: params[:collection_id],
        license: params[:license],
        tags: params[:add_tags]
      )
    end

    redirect_to models_path, notice: t(".success")
  end

  def update
    hash = model_params
    organize = hash.delete(:organize) == "true"
    result = @model.update(hash)
    respond_to do |format|
      format.html do
        if result
          @model.organize_later if organize
          redirect_to @model, notice: t(".success")
        else
          get_creators_and_collections
          edit
          render :edit, status: :unprocessable_entity
        end
      end
      format.manyfold_api_v0 do
        if result
          render json: ManyfoldApi::V0::ModelSerializer.new(@model).serialize
        else
          render json: @model.errors.to_json, status: :unprocessable_entity
        end
      end
    end
  end

  def merge
    if params[:target] && (target = (@model.parents.find { |it| it.public_id == params[:target] }))
      @model.merge_into! target
      redirect_to target, notice: t(".success")
    elsif params[:all] && @model.contains_other_models?
      @model.merge_all_children!
      redirect_to @model, notice: t(".success")
    else
      head :bad_request
    end
  end

  def scan
    # Start the scans
    @model.check_later
    # Back to the model page
    redirect_to @model, notice: t(".success")
  end

  def bulk_edit
    authorize Model
    @models = filtered_models(@filters).includes(:collection, :creator)
    generate_available_tag_list
    if helpers.pagination_settings["models"]
      page = params[:page] || 1
      # Double the normal page size for bulk editing
      @models = @models.page(page).per(helpers.pagination_settings["per_page"] * 2)
    end
    # Apply tag filters in-place
    @filter_in_place = true
  end

  def bulk_update
    authorize Model
    hash = bulk_update_params
    hash[:library_id] = hash.delete(:new_library_id) if hash[:new_library_id]
    organize = hash.delete(:organize) == "1"
    add_tags = Set.new(hash.delete(:add_tags))
    remove_tags = Set.new(hash.delete(:remove_tags))

    models_to_update = if params.key?(:update_all)
      # If "Update All Models" was clicked, update all models in the filtered set
      filtered_models(@filters)
    else
      # If "Update Selected Models" was clicked, only update checked models
      ids = params[:models].select { |k, v| v == "1" }.keys
      policy_scope(Model).where(public_id: ids)
    end

    models_to_update.find_each do |model|
      if model&.update(hash)
        existing_tags = Set.new(model.tag_list)
        model.tag_list = existing_tags + add_tags - remove_tags
        model.save
      end
      model.organize_later if organize
    end
    redirect_back_or_to edit_models_path(@filters), notice: t(".success")
  end

  def destroy
    @model.delete_from_disk_and_destroy
    respond_to do |format|
      format.html do
        if request.referer && (URI.parse(request.referer).path == model_path(@model))
          # If we're coming from the model page itself, we can't go back there
          redirect_to root_path, notice: t(".success")
        else
          redirect_back_or_to root_path, notice: t(".success")
        end
      end
      format.manyfold_api_v0 { head :no_content }
    end
  end

  private

  def redirect_search
    redirect_to new_follow_path(uri: params[:q]) if params[:q]&.match?(/(@|acct:)?([a-z0-9\-_.]+)@(.*)/)
  end

  def generate_available_tag_list
    @available_tags = policy_scope(ActsAsTaggableOn::Tag).where(
      id: policy_scope(ActsAsTaggableOn::Tagging).where(
        taggable_type: "Model", taggable_id: policy_scope(Model).select(:id)
      ).select(:tag_id)
    ).order(:name)
  end

  def bulk_update_params
    params.permit(
      :creator_id,
      :collection_id,
      :new_library_id,
      :organize,
      :license,
      :sensitive,
      add_tags: [],
      remove_tags: []
    ).compact_blank
  end

  def model_params
    if is_api_request?
      raise ActionController::BadRequest unless params[:json]
      ManyfoldApi::V0::ModelDeserializer.new(params[:json]).deserialize
    else
      Form::ModelDeserializer.new(params).deserialize
    end
  end

  def get_model
    @model = policy_scope(Model).find_param(params[:id])
    authorize @model
    @title = @model.name
  end

  def get_creators_and_collections
    # Creators and collections that we can assign this model to
    @creators = policy_scope(Creator, policy_scope_class: ApplicationPolicy::UpdateScope).local.order("LOWER(creators.name) ASC")
    @default_creator = @creators.first if @creators.count == 1
    @collections = policy_scope(Collection, policy_scope_class: ApplicationPolicy::UpdateScope).local.order("LOWER(collections.name) ASC")
  end

  def set_returnable
    session[:return_after_new] = request.fullpath.split("?")[0]
    @new_collection = Collection.find_param(params[:new_collection]) if params[:new_collection]
    @new_creator = Creator.find_param(params[:new_creator]) if params[:new_creator]
    if @model
      @model.collection = @new_collection if @new_collection
      @model.creator = @new_creator if @new_creator
    end
  end

  def clear_returnable
    session[:return_after_new] = nil
  end
end
