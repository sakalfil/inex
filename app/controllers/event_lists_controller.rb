class EventListsController < ApplicationController
  before_action :set_event_list, only: [:set_state, :state, :payment_info, :create_registration_child, :step_second_child, :register_child, :employee_show, :employee_edit, :step_second, :show, :edit, :update, :destroy]
  before_action :can_see_this, only: [:show, :edit, :step_second, :payment_info, :update] # Can see only his own event list
  before_action :employee_check, only: [:state, :employee_show, :employee_edit, :destroy]
  before_action :create_bag
  layout 'page_part'
  layout 'application', only: [:employee_show, :employee_edit, :state]

  def add_volunteer_on_event
    @volunteer = Volunteer.create(event_id: params[:event_id], event_list_id: params[:id])
    redirect_to :back, success: "#{t(:volunteer)} #{define_notice('m', :create)}"
  end

  # Remove Volunteer/Local partner, ...
  def remove_participant_from_event
    classname = params[:classname]
    if %(Volunteer LocalPartner Leader Trainer).include?(classname)
      eval(classname).find(params[:id]).destroy
    end
    respond_to do |format|
      format.html { redirect_to :back, success: "#{classname} #{define_notice('m', :destroy)}" }
    end
  end

  # PUT
  def sort
    params[:order].each do |key, value|
      EventInList.find(value[:id]).update_attribute(:priority, value[:position])
    end
    render :nothing => true
  end

  # GET /event_lists
  def index
    @event_lists = EventList.all
  end

  # POST
  def add_event
    @event      = Event.find(params[:event_id])
    @event_list = EventList.find(params[:id])
    if @event_list.events.include?(@event) # Uz ho obsahuje
      redirect_to :back, warning: t(:event_already_exists_in_your_bag)
    else
      @event_list.event_in_lists.create(event: @event, state: 'opened')
      redirect_to :back, success: t(:event_was_added_to_your_bag)
    end
  end

  # POST
  def remove_event
    @event      = Event.find(params[:event_id])
    @event_list = EventList.find(params[:id])
    if @event_list.events.include?(@event)
      @event_list.event_in_lists.where(event_id: @event.id).destroy_all
      redirect_to :back, success: t(:event_was_removed_from_your_bag)
    else # Nie je tam
      redirect_to :back, warning: t(:event_does_not_exist_in_your_bag)
    end
  end

  # PATCH
  def set_state
    state = params[:state]
    if %(reopened submitted closed pending storno).include?(state)
      @event_list.state = state
      @event_list.save(validate: false)
      redirect_to :back, success: "#{t :bag_was_set_as} #{state}."
    else
      redirect_to :back, error: "Error: #{t :bag_was_set_as} #{state}."
    end
  end

  # GET /event_lists/1
  # GET /event_lists/1.json
  def show
    @events = @event_list.events
  end

  # GET/PUT Nastavenie stavu riesenia eventu v bag
  def state
    @events = @event_list.events
    @event_list.event_in_lists.each do |eil|
      state = params["#{eil.id}"]
      eil.update(state: state) unless state.blank?
    end unless params[:commit].blank?
  end

  # GET
  def employee_show
    @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
    @full_reg_events    = @event_list.events.where(is_simple_registration: [false, nil])
    @inex_member_events = @event_list.events.where(can_create_member_registration: true)
    @events_by_type     = {}
    @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e }
  end

  # GET /event_lists/new
  def new
    @event_list = EventList.new
  end

  # GET /event_lists/1/edit
  def edit
    @educations         = Education.all
    @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
    @full_reg_events    = @event_list.events.where(is_simple_registration: [false, nil])
    @inex_member_events = @event_list.events.where(can_create_member_registration: true)
    @events_by_type     = {}
    @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e }
    if @event_list.addresses.blank? && !current_user.addresses.blank?
      current_user.addresses.each do |user_address|
        address               = user_address.dup
        address.user_id       = nil
        address.event_list_id = @event_list.id
        address.save
      end
    end
  end

  # POST
  def create_registration_child
    children_list = EventList.new(is_child: true, user_id: @event_list.user_id)
    children_list.save(validate: false)
    @event_list.events.each do |e|
      children_list.event_in_lists.create(event_id: e.id)
    end

    redirect_to register_child_event_list_path(children_list)
  end

  # GET
  def register_child
    @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
    @full_reg_events    = @event_list.events.where(is_simple_registration: [false, nil])
    @inex_member_events = @event_list.events.where(can_create_member_registration: true)
    @events_by_type     = {}
    @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e }

    unless params[:commit].blank?
      @event_list.state = 'submitted'
      respond_to do |format|
        if @event_list.update(event_list_params)
          format.html { redirect_to step_second_child_event_list_path(@event_list, form_type: @event_list.form_type, inex_member: @event_list.inex_member), notice: 'Taška dieťaťa bola registrovaná. Čakaj na jej spracovanie.' }
        else
          @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
          @full_reg_events    = @event_list.events.where(is_simple_registration: [false, nil])
          @inex_member_events = @event_list.events.where(can_create_member_registration: true)
          @events_by_type     = {}
          @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e }
          format.html { render :register_child }
        end
      end
    end
  end

  # GET /event_lists/1/edit
  def employee_edit
    @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
    @full_reg_events    = @event_list.events.where(is_simple_registration: [false, nil])
    @inex_member_events = @event_list.events.where(can_create_member_registration: true)
    @events_by_type     = {}
    @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e }
    if @event_list.addresses.blank? && !current_user.addresses.blank?
      current_user.addresses.each do |user_address|
        address               = user_address.dup
        address.user_id       = nil
        address.event_list_id = @event_list.id
        address.save
      end
    end

    unless params[:commit].blank?
      @event_list.check_conditions_agreement = false
      respond_to do |format|
        if @event_list.update(event_list_params)
          format.html { redirect_to event_types_path, success: "#{t :bag} #{define_notice('ž', :update)}" }
        else
          @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
          @full_reg_events    = @event_list.events.where(is_simple_registration: [false, nil])
          @inex_member_events = @event_list.events.where(can_create_member_registration: true)
          @events_by_type     = {}
          @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e }
          format.html { render :employee_edit }
        end
      end
    end
  end

  # GET/PUT
  def step_second
    @event_list.form_type                  = params[:form_type]
    @event_list.check_conditions_agreement = false
    if @event_list.invalid?
      redirect_to edit_event_list_path(@event_list), error: t(:there_is_some_error_in_form)
      return
    end

    @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
    @full_reg_events    = @event_list.events.where(is_simple_registration: [false, nil])
    @inex_member_events = @event_list.events.where(can_create_member_registration: true)
    @events_by_type     = {}
    @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e if e.can_be_registered(current_user) }
    if @event_list.addresses.blank? && !current_user.addresses.blank?
      current_user.addresses.each do |user_address|
        address               = user_address.dup
        address.user_id       = nil
        address.event_list_id = @event_list.id
        address.save
      end
    end

    # send it! create registrations (simple/full) for event_lists grouped by type
    # can_register_event?
    # state: 'submitted'
    # send mail if you should
    # destroy actual event list if you haven't done it in previous steps ;)
    unless params[:commit].blank? && (@event_list.state == 'opened' || @event_list.state == 'reopened')
      @simple_events_by_type = {}
      @simple_reg_events.each do |e|
        if e.can_be_registered(current_user)
          @simple_events_by_type[e.event_type] ||= []
          @simple_events_by_type[e.event_type] << e
        end
      end
      @full_events_by_type = {}
      @full_reg_events.each do |e|
        if e.can_be_registered(current_user)
          @full_events_by_type[e.event_type] ||= []
          @full_events_by_type[e.event_type] << e
        end
      end

      if @simple_events_by_type.any?
        @simple_events_by_type.each do |event_type, events|
          el       = @event_list.dup # duplicate also addresses, language_skills
          el.state = 'submitted'
          el.save(validate: false)
          events.each do |event|
            el.event_in_lists.create(event_id: event.id)
          end
          # TU PRE KAZDY TYP JEDEN MAIL PRE ZAMESTNANCA, ak nie je nastavene, ze netreba
          if event_type.employee && event_type.can_send_registration_mail
            if event_type.employee.work_mail
              employee_mail = event_type.employee.work_mail
            else
              employee_mail = event_type.employee.try(:user).try(:login_mail)
            end
            RegisteredBagMailer.registered_bag_employee(employee_mail, el, "#{request.protocol}#{request.host_with_port}").deliver_now
          end
          RegisteredBagMailer.registered_bag(@event_list.personal_mail, el, "#{request.protocol}#{request.host_with_port}").deliver_now
        end
      end

      if @full_events_by_type.any?
        @full_events_by_type.each do |event_type, events|
          el       = @event_list.dup # duplicate also addresses, language_skills
          el.state = 'submitted'
          el.save(validate: false)
          events.each do |event|
            el.event_in_lists.create(event_id: event.id)
          end
          @event_list.addresses.each do |address|
            a               = address.dup
            a.event_list_id = el.id
            a.save(validate: false)
          end
          @event_list.language_skills.each do |ls|
            a               = ls.dup
            a.event_list_id = el.id
            a.save(validate: false)
          end

          # TU PRE KAZDY TYP JEDEN MAIL PRE ZAMESTNANCA, ak nie je nastavene, ze netreba
          if event_type.employee && event_type.can_send_registration_mail
            if event_type.employee.work_mail
              employee_mail = event_type.employee.work_mail
            else
              employee_mail = event_type.employee.try(:user).try(:login_mail)
            end
            RegisteredBagMailer.registered_bag_employee(employee_mail, el, "#{request.protocol}#{request.host_with_port}").deliver_now
          end
          RegisteredBagMailer.registered_bag(@event_list.personal_mail, el, "#{request.protocol}#{request.host_with_port}").deliver_now
        end
      end

      if params[:inex_member] == '1'
        el       = @event_list.dup
        el.state = 'submitted'
        el.save(validate: false)
        member_event = Event.find_by_title('Prihlášky za člena')
        el.event_in_lists.create(event_id: member_event.id)
        @event_list.addresses.each do |address|
          a               = address.dup
          a.event_list_id = el.id
          a.save(validate: false)
        end
        # TU JEDEN MAIL PRE ZAMESTNANCA O CLENSKOM
        event_type = member_event.try(:event_type)
        if event_type.try(:employee) && event_type.try(:can_send_registration_mail)
          if !event_type.employee.work_mail.blank?
            employee_mail = event_type.employee.work_mail
          else
            employee_mail = event_type.employee.try(:user).try(:login_mail)
          end
          RegisteredBagMailer.registered_bag_employee(employee_mail, el, "#{request.protocol}#{request.host_with_port}").deliver_now
        end
        #RegisteredBagMailer.registered_bag(el.personal_mail, el, "#{request.protocol}#{request.host_with_port}").deliver_now
      end

      @event_list.destroy
      redirect_to current_user, success: t(:your_application_was_submitted)
    end
  end

  # GET/PUT
  def step_second_child
    @event_list.form_type                  = params[:form_type]
    @event_list.check_conditions_agreement = false
    if @event_list.invalid?
      redirect_to edit_event_list_path(@event_list), error: t(:there_is_some_error_in_form)
      return
    end

    @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
    @full_reg_events    = @event_list.events.where(is_simple_registration: false) + @event_list.events.where(is_simple_registration: nil)
    @inex_member_events = @event_list.events.where(can_create_member_registration: true)
    @events_by_type     = {}
    @event_list.events.each do |e|
      if e.can_be_registered(current_user)
        @events_by_type[e.event_type] ||= []
        @events_by_type[e.event_type] << e
      end
    end
    if @event_list.addresses.blank? && !current_user.addresses.blank?
      current_user.addresses.each do |address|
        a               = address.dup
        a.user_id       = nil
        a.event_list_id = @event_list.id
        a.save
      end
    end
    event_type = @event_list.event_type
    if event_type && event_type.employee && event_type.can_send_registration_mail
      if event_type.employee.work_mail
        employee_mail = event_type.employee.work_mail
      else
        employee_mail = event_type.employee.try(:user).try(:login_mail)
      end
      RegisteredBagMailer.registered_bag_employee(employee_mail, @event_list, "#{request.protocol}#{request.host_with_port}").deliver_now
    end
    RegisteredBagMailer.registered_bag(@event_list.personal_mail, @event_list, "#{request.protocol}#{request.host_with_port}").deliver_now

    if params[:inex_member] == '1'
      el          = @event_list.dup
      el.is_child = true
      el.state    = 'submitted'
      el.save(validate: false)
      member_event = Event.find_by_title('Prihlášky za člena')
      el.event_in_lists.create(event_id: member_event.id)
      @event_list.addresses.each do |address|
        a               = address.dup
        a.event_list_id = el.id
        a.save(validate: false)
      end
      event_type = member_event.try(:event_type)
      if event_type.try(:employee) && event_type.try(:can_send_registration_mail)
        if !event_type.employee.work_mail.blank?
          employee_mail = event_type.employee.work_mail
        else
          employee_mail = event_type.employee.try(:user).try(:login_mail)
        end
        RegisteredBagMailer.registered_bag_employee(employee_mail, el, "#{request.protocol}#{request.host_with_port}").deliver_now
      end
    end
  end

  # POST /event_lists
  def create
    @event_list = EventList.new(event_list_params)

    respond_to do |format|
      if @event_list.save
        format.html { redirect_to @event_list, success: "#{t :bag} #{define_notice('ž', __method__)}" }
      else
        format.html { render :new }
      end
    end
  end

  # PATCH/PUT /event_lists/1
  # PATCH/PUT /event_lists/1.json
  def update
    respond_to do |format|
      if @event_list.update(event_list_params)
        format.html { redirect_to step_second_event_list_path(@event_list, form_type: @event_list.form_type, inex_member: @event_list.inex_member), success: "#{t :bag} #{define_notice('ž', __method__)}" }
      else
        @educations         = Education.all
        @simple_reg_events  = @event_list.events.where(is_simple_registration: true)
        @full_reg_events    = @event_list.events.where(is_simple_registration: false) + @event_list.events.where(is_simple_registration: nil)
        @inex_member_events = @event_list.events.where(can_create_member_registration: true)
        @events_by_type     = {}
        @event_list.events.each { |e| (@events_by_type[e.event_type] ||= []) << e }
        format.html { render :edit }
      end
    end
  end

  # DELETE /event_lists/1
  # DELETE /event_lists/1.json
  def destroy
    @event_list.destroy
    respond_to do |format|
      format.html { redirect_to :back, success: "#{t :bag}  #{define_notice('ž', __method__)}" }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_event_list
    @event_list = EventList.find(params[:id])
  end

  # Create opened bag if does not exist
  def create_bag
    if !current_user
      redirect_to root_path, warning: t(:to_edit_your_bag_you_should_be_logged_in)
    end
  end

  def can_see_this
    unless (current_user && (current_user.is_inex_office? || current_user == @event_list.user))
      redirect_to root_path, error: t(:you_dont_have_permissions_to_perform_this_action)
    end
  end

  def employee_check
    if (@event_list.state != 'opened' || @event_list.state != 'reopened') && current_user && !current_user.is_inex_office?
      redirect_to root_path, error: t(:you_dont_have_permissions_to_perform_this_action)
    end
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def event_list_params
    params.require(:event_list).permit(:state, :result, :login_mail, :name, :surname,
                                       :nickname, :personal_mail, :personal_phone,
                                       :birth_date, :place_of_birth, :nationality,
                                       :occupation, :other_contacts, :sex,
                                       :emergency_name, :emergency_mail, :emergency_phone,
                                       :experiences, :why, :remarks, :on_health,
                                       :conditions_agreement, :form_type, :inex_member,
                                       :children_count, :education_id,
                                       language_skills_attributes: [:language_id, :level, :id, :_destroy],
                                       addresses_attributes:       [:id, :address, :city, :country, :postal_code, :title, :_destroy])
  end

end
