require 'test_helper'

class ApiTest < ActionDispatch::IntegrationTest
  setup do
    @api_user = FactoryBot.create(:user, :api, :editor)
    @api_user_no_edit = FactoryBot.create(:user, :api)
    @ordinary_user = FactoryBot.create(:user)
    @staff1 = FactoryBot.create(
      :staff, {name: "Able Baker Charlie", initials: "ABC"})
    @pupil1 = FactoryBot.create(:pupil, name: "Fotheringay-Smith Maximus")
    @pupil2 = FactoryBot.create(:pupil, name: "Fotheringay-Smith Major")
    @pupil3 = FactoryBot.create(:pupil, name: "Fotheringay-Smith Minor")
    @pupil4 = FactoryBot.create(:pupil, name: "Fotheringay-Smith Minimus")
    @group1 = FactoryBot.create(:group)
    @location1 = FactoryBot.create(:location)
    @property1 = FactoryBot.create(:property)
    @service1 = FactoryBot.create(:service)
    @subject1 = FactoryBot.create(:subject)
    @resourcegroup = FactoryBot.create(:resourcegroup)
    #
    #  You can't create events unless this event source exists.
    #
    @eventsource = FactoryBot.create(:eventsource, name: 'API')
    @eventcategory = FactoryBot.create(:eventcategory, name: 'Test API events')
    @event_start_time = Time.zone.now
    @event_end_time = Time.zone.now + 1.hour
    @valid_event_params = {
      body:           'My test event',
      starts_at_text: @event_start_time.strftime("%d/%m/%Y %H:%M"),
      ends_at_text:   @event_end_time.strftime("%d/%m/%Y %H:%M"),
      eventcategory_id: @eventcategory.id
    }
    @elements_to_add = [
      @staff1.element,
      @pupil1.element,
      @location1.element,
      @resourcegroup.element
    ]
    @element_ids_to_add = @elements_to_add.collect {|e| e.id}

    @api_paths = PublicApi::Engine.routes.url_helpers
  end

  #
  #  Basic login and logout
  #
  test "login requests must be json" do
    get @api_paths.login_path(uid: @api_user.uuid)
    assert_redirected_to "/"
  end

  test "random uid does not log in" do
    get @api_paths.login_path(uid: 'ablebakercharlie'), format: :json
    assert_response 401         # Unauthorized
  end

  test "ordinary user cannot log in through api" do
    get @api_paths.login_path(uid: @ordinary_user.uuid), format: :json
    assert_response 401         # Unauthorized
  end

  test "api user can log in through api" do
    get @api_paths.login_path(uid: @api_user.uuid), format: :json
    assert_response :success
  end

  test "logout requests must be json" do
    get @api_paths.logout_path
    assert_redirected_to "/"
  end

  test "logout always succeeds" do
    get @api_paths.logout_path, format: :json
    assert_response :success
  end

  #
  #  Login required for other actions
  #  After logout, actions no longer available.
  #
  test "authentication required" do
    #
    #  Initially can't issue an arbitrary request.
    #
    get @api_paths.elements_path, format: :json
    assert_response 401         # Unauthorized
    #
    #  Then login and we can.
    #
    do_valid_login
    get @api_paths.elements_path, format: :json
    assert_response :success
    #
    #  Then logout and we can't again.
    #
    do_logout
    get @api_paths.elements_path, format: :json
    assert_response 401         # Unauthorized
  end

  #
  #  Now test the elements controller.
  #
  test "index with no params gets empty response" do
    do_valid_login
    get @api_paths.elements_path, format: :json
    assert_response :success
    data = JSON.parse(response.body)
    status = data['status']
    elements = data['elements']
    assert_equal "OK", status
    #
    #  elements should be an empty array.
    #
    assert_instance_of Array, elements
    assert_empty elements
  end

  test "search for non-existent element returns appropriate error" do
    do_valid_login
    get @api_paths.elements_path(name: 'Banana fritter'), format: :json
    assert_response :missing
  end

  test "search for existing element finds it" do
    do_valid_login
    get @api_paths.elements_path(name: 'ABC - Able Baker Charlie'),
        format: :json
    assert_response :success
    data = JSON.parse(response.body)
    status = data['status']
    elements = data['elements']
    assert_equal "OK", status
    assert_instance_of Array, elements
    assert_equal 1, elements.size
    check_element_summary(elements[0])
  end

  test "fuzzy search for non-existent element returns appropriate error" do
    do_valid_login
    get @api_paths.elements_path(namelike: 'Banana fritter'), format: :json
    assert_response :missing
  end

  test "fuzzy search finds existing elements" do
    do_valid_login
    get @api_paths.elements_path(namelike: 'Fotheringay'),
        format: :json
    assert_response :success
    data = JSON.parse(response.body)
    status = data['status']
    elements = data['elements']
    assert_equal "OK", status
    assert_instance_of Array, elements
    assert_equal 4, elements.size
    elements.each do |element|
      check_element_summary(element)
    end
  end

  test "element show with invalid id returns appropriate error" do
    do_valid_login
    get @api_paths.element_path(id: 999), format: :json
    assert_response :missing
    data = JSON.parse(response.body)
    status = data['status']
    assert_equal "Not found", status
  end

  test "element show succeeds for valid staff element" do
    do_valid_login
    do_show_element(@staff1.element)
  end

  test "element show succeeds for valid pupil element" do
    do_valid_login
    do_show_element(@pupil1.element)
  end

  test "element show succeeds for valid group element" do
    do_valid_login
    do_show_element(@group1.element)
  end

  test "element show succeeds for valid location element" do
    do_valid_login
    do_show_element(@location1.element)
  end

  test "element show succeeds for valid property element" do
    do_valid_login
    do_show_element(@property1.element)
  end

  test "element show succeeds for valid service element" do
    do_valid_login
    do_show_element(@service1.element)
  end

  test "element show succeeds for valid subject element" do
    do_valid_login
    do_show_element(@subject1.element)
  end

  #
  #  And now the events controller
  #
  test "event create without params fails" do
    do_valid_login
    post @api_paths.events_path, format: :json
    assert_response 400         # Bad request
  end

  test "event create with valid params succeeds" do
    do_valid_login
    post @api_paths.events_path(event: @valid_event_params), format: :json
    assert_response 201         # Created
  end

  test "unauthorized user can't create event" do
    do_valid_login(@api_user_no_edit)
    post @api_paths.events_path(event: @valid_event_params), format: :json
    assert_response 403         # Forbidden
  end

  test "can add elements whilst creating" do
    do_valid_login
    post @api_paths.events_path(
      event: @valid_event_params,
      elements: @element_ids_to_add
    ), format: :json
    assert_response 201         # Created
    #puts response.body
    response_data = JSON.parse(response.body)
    #
    #  Check textual status
    #
    status = response_data['status']
    assert_equal 'Created', status
    #
    #  Check for failures - there should be none.
    #
    failures = response_data['failures']
    assert_instance_of Array, failures
    assert_empty failures
    #
    #  And check the event has the right fields, plus the right number
    #  of commitments and requests.
    #
    event = response_data['event']
    assert_instance_of Hash, event
    assert_equal @valid_event_params[:body], event['body']
    compare_times @valid_event_params[:starts_at_text], event['starts_at']
    compare_times @valid_event_params[:ends_at_text], event['ends_at']
    assert_not event['all_day']
    #
    #  How many should be commitments and how many requests?
    #
    for_requests, for_commitments =
      @elements_to_add.partition {|e| e.can_have_requests?}
    assert_equal for_requests.size,
      event['requests'].size
    assert_equal for_commitments.size,
      event['commitments'].size
  end

  test 'two entries for same requestable item result in one request' do
    do_valid_login
    post @api_paths.events_path(
      event: @valid_event_params,
      elements: [@resourcegroup.element.id, @resourcegroup.element.id]
    ), format: :json
    assert_response 201         # Created
    response_data = JSON.parse(response.body)
    #
    #  Check for failures - there should be none.
    #
    failures = response_data['failures']
    assert_instance_of Array, failures
    assert_empty failures
    #
    #  Should have one request, with a quantity of 2.
    #
    event = response_data['event']
    assert_instance_of Hash, event
    requests = event['requests']
    assert_equal 1, requests.size
    assert_equal 2, requests[0]['quantity']
  end

  test 'two entries for same ordinary item result in a failure' do
    do_valid_login
    post @api_paths.events_path(
      event: @valid_event_params,
      elements: [@staff1.element.id, @staff1.element.id]
    ), format: :json
    assert_response 201         # Created
    response_data = JSON.parse(response.body)
    #
    #  Check for failures - there should be one.
    #
    failures = response_data['failures']
    assert_instance_of Array, failures
    assert_equal 1, failures.size
    #
    #  Should have just one commitment.
    #
    event = response_data['event']
    assert_instance_of Hash, event
    commitments = event['commitments']
    assert_equal 1, commitments.size
  end

  test 'can add elements after creating event' do
    do_valid_login
    post @api_paths.events_path(
      event: @valid_event_params
    ), format: :json
    assert_response 201         # Created
    response_data = JSON.parse(response.body)
    #
    #  Check textual status
    #
    status = response_data['status']
    assert_equal 'Created', status
    #
    #  We have our event - now add to it.
    #
    event = response_data['event']
    assert_instance_of Hash, event
    event_id = event['id']

    post @api_paths.add_event_path(event_id,
                                   elements: @element_ids_to_add),
                                   format: :json
    assert_response :success
    response_data = JSON.parse(response.body)
    #
    #  Check for failures - there should be none.
    #
    failures = response_data['failures']
    assert_instance_of Array, failures
    assert_empty failures
    #
    #  And check the event has the right number
    #  of commitments and requests.
    #
    event = response_data['event']
    assert_instance_of Hash, event
    #
    #  How many should be commitments and how many requests?
    #
    for_requests, for_commitments =
      @elements_to_add.partition {|e| e.can_have_requests?}
    assert_equal for_requests.size,
      event['requests'].size
    assert_equal for_commitments.size,
      event['commitments'].size
  end

  private

  def do_valid_login(user = @api_user)
    get @api_paths.login_path(uid: user.uuid), format: :json
    assert_response :success
  end

  def do_logout
    get @api_paths.logout_path, format: :json
    assert_response :success
  end

  def do_show_element(element)
    #
    #  This handles only the positive case.  The element should
    #  exist in the database.
    #
    get @api_paths.element_path(element), format: :json
    assert_response :ok
    data = JSON.parse(response.body)
    status = data['status']
    element_data = data['element']
    assert_equal "OK", status
    assert_equal element.id, element_data['id']
    #
    #  Note that these might have a value of nil, but they should still
    #  be there.
    #
    assert element_data.key?('name')
    assert element_data.key?('entity_type')
    assert element_data.key?('entity_id')
    assert element_data.key?('current')
    case element.entity_type
    when 'Pupil'
      assert element_data.key?('email')
      assert element_data.key?('forename')
      assert element_data.key?('surname')
      assert element_data.key?('known_as')
      assert element_data.key?('year_group')
      assert element_data.key?('house_name')
    when 'Staff'
      assert element_data.key?('email')
      assert element_data.key?('title')
      assert element_data.key?('initials')
      assert element_data.key?('forename')
      assert element_data.key?('surname')
    when 'Group'
      assert element_data.key?('description')
    when 'Property'
      assert element_data.key?('make_public')
      assert element_data.key?('auto_staff')
      assert element_data.key?('auto_pupils')
    end
  end

  def check_element_summary(summary)
    assert summary.key?('id')
    assert summary.key?('name')
    assert summary.key?('entity_type')
    assert summary.key?('entity_id')
  end

  def compare_times(expected, actual)
    #
    #  expected is what we sent
    #  actual is what we got back
    #
    #  Both are strings, but formatted differently.
    #
    assert_equal Time.zone.parse(expected), Time.zone.parse(actual)
  end

end

