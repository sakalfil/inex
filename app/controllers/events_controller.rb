class EventsController < ApplicationController
  before_action :set_event, only: [:show, :show_public, :toggle_is_published, :step_second, :step_third, :step_fourth, :step_fifth, :edit, :update, :destroy, :personalized_detail]
  before_action :set_event_type, only: [:new, :step_second, :step_third, :step_fourth, :step_fifth, :show, :edit, :update, :destroy]
  before_action :can_do_member_actions, except: [:show_public]
  layout 'page_part', :only => [:show_public]
  include Searchable
  include EventsHelper

  def personalized_detail
    @volunteers = @event.volunteers.includes(:event_list).where(event_lists: { user_id: session[:user_id] })
    @leaders = @event.leaders.where(user_id: session[:user_id])
    @local_partners = @event.local_partners.where(user_id: session[:user_id])
    @trainers = @event.trainers.where(user_id: session[:user_id])
    @event_type = @event.event_type
  end

  # EventType/show
  def search
    results = do_search(Event.includes(:event_type), columns: [:title, :from, :to, :country, :code, :code_alliance], order_by: { from: :desc })
    results = results.collect { |e| [event_title_link(e, view_context), e.from_to, states_html(e, view_context), action_links(e, view_context)] }
    render json: {
      "draw":            params[:draw],
      "recordsTotal":    Event.count,
      "recordsFiltered": Event.count,
      "data":            results
    }
  end

  # EventType/_panel
  def search_events
    results = Event.includes(:event_type).where_or_regexp(columns: [:title, :from, :to, :country, :code, :code_alliance], string: params[:q]).order(:from)
    results = results.collect { |e|
      {
        "title":       "#{e.translated_title}",
        "url":         event_type_event_path(e.event_type, e),
        "description": e.event_type.try(:title)
      }
    }
    render json: {
      "results": results,
      "action":  {
        "url":  "#",
        "text": "#{results.size} výsledkov"
      }
    }
  end

  # Identifikacia stlpcov a vyplnenie zmien
  def import_2
    if params[:commit]
      if !params[:file].blank?
        begin
          file = File.join("public", "system", "files", "#{DateTime.now}_#{params[:file].original_filename}")
          FileUtils.cp params[:file].tempfile.path, file
          event_importer                  = EventImporter.new(file)
          @file                           = event_importer.csvify
          @event_column_set, @file_header = event_importer.get_database_columns_for_file_columns(@file)
        rescue Exception => e
          redirect_to :back, error: e.message
        end
      else
        redirect_to :back, warning: 'Nebol vybraný súbor.'
      end
    end
  end

  # Zmeny stlpcov a navrh zmien
  def import_3
    @file = params[:file]
    if params[:commit] && params[:file]
      event_importer                                          = EventImporter.new(params[:file])
      @event_column_set, my_theirs, @header                   = event_importer.update_event_column_set(params, @file)
      @new, @changed, @unchanged, @errors, @ignored, @changes = event_importer.get_event_changes(@file, @event_column_set, my_theirs).values_at(:new, :changed, :unchanged, :errors, :ignored, :changes)
    end
  end

  # Zmeny stlpcov a navrh zmien
  def import_4
    @file = params[:file]
    if params[:commit] && params[:file]
      if !params[:event_column_set_id].blank?
        event_importer    = EventImporter.new(params[:file])
        @event_column_set = EventColumnSet.find(params[:event_column_set_id])
        @header           = event_importer.get_header(@file)
        my_theirs         = {} # Hash {my => [their1, their2, ...]}
        @header.each do |header|
          @event_column_set.event_columns.where(their: header).each { |e| (my_theirs[e.my] ||= [])<< e.their }
        end
      else
        redirect_to import_1_events_path, error: "Nastala chyba pri vyhodnocovaní zmien eventov."
      end
      @new, @changed, @errors = event_importer.make_event_changes(@file, @event_column_set, params[:make_changes], my_theirs).values_at(:new, :changed, :errors)
      @header                 = event_importer.event_columns
    end
  end

  # PUT
  def toggle_is_published
    @event.update(is_published: !@event.is_published)
    redirect_to :back, success: "Stav publikovania eventu bol úspešne zmenený."
  end

  # GET /events
  def index
    @events = Event.all
  end

  # GET /events/1
  def show
    prawnto :prawn => { :page_size => 'A4', :page_layout => :landscape } # Prezenčka
    @leaders        = @event.leaders
    @trainers       = @event.trainers
    @local_partners = @event.local_partners
    @volunteers     = @event.volunteers
    if !@event.country.blank? && !Country.where(name: @event.country).any?
      @event.errors.add(:country, "Krajina #{@event.country} nie je v zozname krajín. Nemôže sa tak zobraziť na mape.")
    end
  end

  # GET /events/1/show_public
  def show_public
    if !@event.is_published && !current_user.try(:is_inex_office?)
      redirect_to root_path, error: 'Vybraný tábor nie je publikovaný.'
    end
  end

  # GET /events/new
  def new
    @event         = Event.new
    @organizations = Organization.all
  end

  # GET/PATCH
  def step_fourth
    @users          = User.all.collect {
      |u|
      u.id   = u.id
      u.name = u.name_with_mail
      u
    }
    @trainers       = Trainer.joins(:user).select(:id, :user_id, :nickname)
    @local_partners = LocalPartner.joins(:user).select(:id, :user_id, :nickname)
    @leaders        = Leader.joins(:user).select(:id, :user_id, :nickname)
  end

  # GET /events/1/edit
  def edit
    @organizations = Organization.all
  end

  # POST /events
  def create
    @event = Event.new(event_params)

    respond_to do |format|
      if @event.save
        format.html { redirect_to step_second_event_type_event_path(@event.event_type, @event), success: "Event  #{define_notice('m', __method__)}" }
      else
        @organizations = Organization.all
        format.html { render :new }
      end
    end
  end

  # Helper method
  def next_step_path(step, event_type, event)
    case step
      when 'first'
        step_second_event_type_event_path(event_type, event)
      when 'second'
        step_third_event_type_event_path(event_type, event)
      when 'third'
        step_fourth_event_type_event_path(event_type, event)
      when 'fourth'
        step_fifth_event_type_event_path(event_type, event)
      else
        [event_type, event]
    end
  end

  # PATCH/PUT /events/1
  def update
    if params[:actual_step] == 'second'
      if @event.gps_needs_to_be_refreshed?(params[:event][:gps_latitude], params[:event][:gps_longitude])
        if @event.address.blank? && params[:event]
          address = params[:event][:address]
        else
          address = @event.address
        end
        if @event.city.blank? && params[:event]
          city = params[:event][:city]
        else
          city = @event.city
        end
        if params[:event] # tu staci aktualna, nezavisi, co bolo nastavene predtym
          country = params[:event][:country]
        else
          country = @event.country
        end
        coords = Geocoder.coordinates("#{address} #{city} #{country}")
        if coords
          params[:event][:gps_latitude]  = coords[0]
          params[:event][:gps_longitude] = coords[1]
        else
          flash[:warning] = "GPS sa nedokázali vypočítať"
        end
      end
    end

    if params[:actual_step] == 'fourth'
      @event.trainers.destroy_all
      @event.local_partners.destroy_all
      @event.leaders.destroy_all

      params[:trainer_ids].each do |id|
        @event.trainers.create(user_id: id)
      end unless params[:trainer_ids].blank?

      params[:local_partner_ids].each do |id|
        @event.local_partners.create(user_id: id)
      end unless params[:local_partner_ids].blank?

      params[:leader_ids].each do |id|
        @event.leaders.create(user_id: id)
      end unless params[:leader_ids].blank?
    end

    if params[:actual_step] == 'fifth'
      @event.event_with_categories.destroy_all
      params[:categories].each do |c_id|
        @event.event_with_categories.create(event_category_id: c_id.to_i)
      end if !params[:categories].blank?
    end
    respond_to do |format|
      if @event.update(event_params)
        format.html { redirect_to next_step_path(params[:actual_step], @event_type, @event), success: "Event  #{define_notice('m', __method__)}" }
      else
        @organizations = Organization.all
        method         = params[:actual_step] == "first" ? :edit : "step_#{params[:actual_step]}"
        format.html { render method }
      end
    end
  end

  # DELETE /events/1
  def destroy
    @event.destroy
    respond_to do |format|
      if @event.event_type
        format.html { redirect_to @event.event_type, success: "Event  #{define_notice('m', __method__)}" }
      else
        format.html { redirect_to event_types_path, success: "Event  #{define_notice('m', __method__)}" }
      end
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_event
    @event = Event.find(params[:id])
  end

  def set_event_type
    @event_type = EventType.find(params[:event_type_id])
  end

  def can_do_member_actions
    if !(current_user && current_user.is_inex_office?)
      redirect_to root_path
    end
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def event_params
    params.require(:event).permit(:address, :airport, :bus_train, :city, :country, :gps_latitude,
                                  :gps_longitude, :event_type_id,
                                  :capacity_men, :capacity_women, :capacity_total,
                                  :free_men, :free_women, :free_total, :ignore_sex_for_capacity,
                                  :min_age, :max_age, :code, :code_alliance,
                                  :fees_sk, :fees_en, :notes, :title, :title_en,
                                  :description_en, :description_sk, :from, :to, :is_only_date,
                                  :organization_id, :registration_deadline,
                                  :is_simple_registration, :can_create_member_registration,
                                  :evaluation_url_leader, :evaluation_deadline_leader,
                                  :evaluation_url_local_partner, :evaluation_deadline_local_partner,
                                  :evaluation_url_volunteer, :evaluation_deadline_volunteer,
                                  :leader_ids, :trainer_ids, :local_partner_ids,
                                  :is_published, :introduction_sk, :type_of_work_sk, :study_theme_sk,
                                  :accomodation_sk, :camp_advert_sk, :required_spoken_language,
                                  :language_description_sk, :requirements_sk, :location_sk,
                                  :additional_camp_notes_sk, :introduction_en, :type_of_work_en,
                                  :study_theme_en, :accomodation_en, :camp_advert_en,
                                  :language_description_en, :requirements_en, :location_en,
                                  :additional_camp_notes_en, :is_cancelled,
                                  extra_fees_attributes:      [:name, :amount, :currency, :is_paid_to_inex, :id, :_destroy],
                                  event_documents_attributes: [:title, :is_mandatory, :id, :_destroy]
    )
  end

end
