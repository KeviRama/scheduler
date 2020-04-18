require 'test_helper'

class EventTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:user)
    @eventcategory = FactoryBot.create(:eventcategory)
    @eventsource   = FactoryBot.create(:eventsource)
    @confidential_ec = FactoryBot.create(:eventcategory, confidential: true)
    @property = FactoryBot.create(:property)
    @location = FactoryBot.create(:location)
    @valid_params = {
      body: "A test event",
      eventcategory: @eventcategory,
      eventsource: @eventsource,
      starts_at: Time.zone.now,
      ends_at: Time.zone.now + 1.hour
    }
    # Event For Journaling
    # 
    # Use a separate eventsource to avoid clashes.
    #
    @efj_eventsource = FactoryBot.create(:eventsource)
    @efj = FactoryBot.create(
      :event,
      @valid_params.merge({
        eventsource: @efj_eventsource
      })
    )
    @commitment = FactoryBot.create(:commitment, event: @efj)
    @resource = FactoryBot.create(:service)
    @request = FactoryBot.create(:request, event: @efj)
    @note = FactoryBot.create(:note)
    @ufr = FactoryBot.create(:user_form_response)
  end

  test "event factory can add commitments" do
    event = FactoryBot.create(:event, commitments_to: [@property, @location])
    assert_equal 2, event.resources.count
  end

  test "event factory can add requests" do
    event = FactoryBot.create(:event, requests_for: { @property => 2 })
    assert_equal 1, event.requests.count
    assert_equal 2, event.requests[0].quantity
  end

  test "should have a confidential flag" do
    event = FactoryBot.create(:event)
    assert event.respond_to?(:confidential?)
  end

  test "confidential flag should mirror that in event category" do
    event = FactoryBot.create(:event, eventcategory: @eventcategory)
    assert_not event.confidential?
    event = FactoryBot.create(:event, eventcategory: @confidential_ec)
    assert event.confidential?
  end

  test "can create an event" do
    e = Event.create(@valid_params)
    assert e.valid?
  end

  test "must have a body" do
    e = Event.create(@valid_params.except(:body))
    assert_not e.valid?
  end

  test "must have an eventcategory" do
    e = Event.create(@valid_params.except(:eventcategory))
    assert_not e.valid?
  end

  test "must have an eventsource" do
    e = Event.create(@valid_params.except(:eventsource))
    assert_not e.valid?
  end

  test "must have a starts_at" do
    e = Event.create(@valid_params.except(:starts_at))
    assert_not e.valid?
  end

  test "beginning scope has correct cut off" do
    tomorrow_midnight = Date.today + 2.days
    e = Event.create({
      body: "A test event",
      eventcategory: @eventcategory,
      eventsource: @eventsource,
      starts_at: Time.zone.now,
      ends_at: tomorrow_midnight
    })
    assert e.valid?
    assert_equal 1, @eventsource.events.beginning(Date.today).count
    assert_equal 1, @eventsource.events.beginning(Date.tomorrow).count
    assert_equal 0, @eventsource.events.beginning(Date.today + 2.days).count
  end

  test "can add simple commitments" do
    event = FactoryBot.create(:event)
    staff = FactoryBot.create(:staff)
    commitment = event.commitments.create({
      element: staff.element
    })
    assert commitment.valid?
    assert_equal 1, event.staff.count
  end

  test "cloning an event clones simple commitments" do
    event = FactoryBot.create(:event)
    staff = FactoryBot.create(:staff)
    user = FactoryBot.create(:user)
    commitment = event.commitments.create({
      element: staff.element
    })
    assert commitment.valid?
    new_event = event.clone_and_save(user, {})
    assert new_event.valid?
    assert_equal 1, new_event.commitments.size
    assert_not_equal event.commitments.first, new_event.commitments.first
  end

  test "cloning an event clones requests" do
    event = FactoryBot.create(:event)
    resourcegroup = FactoryBot.create(:resourcegroup)
    user = FactoryBot.create(:user)
    request = event.requests.create({
      element: resourcegroup.element,
      quantity: 1
    })
    assert request.valid?
    #
    #    This reload shouldn't be necessary, but there appears to be
    #    a bug in ActiveRecord which makes the request appear twice
    #    in the array.  The count is 1, but the size is 2 and if you
    #    iterate through then the same record appears twice.
    #
    event.reload
    new_event = event.clone_and_save(user, {})
    assert new_event.valid?
    assert_equal 1, new_event.requests.size
    assert_not_equal event.requests.first, new_event.requests.first
  end

  test "cloning an event does not copy commitment fulfilling request" do
    event = FactoryBot.create(:event)
    resourcegroup = FactoryBot.create(:resourcegroup)
    resource1 = FactoryBot.create(:service)
    resource2 = FactoryBot.create(:service)
    resourcegroup.add_member(resource1)
    resourcegroup.add_member(resource2)
    assert_equal 2, resourcegroup.members.size

    user = FactoryBot.create(:user)
    request = event.requests.create({
      element: resourcegroup.element,
      quantity: 2
    })
    assert request.valid?
    request.fulfill(resource1.element)
    assert_equal 1, request.num_allocated, "Num allocated"
    assert_equal 1, request.num_outstanding, "Num outstanding"

    #
    #    This reload shouldn't be necessary, but there appears to be
    #    a bug in ActiveRecord which makes the request appear twice
    #    in the array.  The count is 1, but the size is 2 and if you
    #    iterate through then the same record appears twice.
    #
    event.reload
    new_event = event.clone_and_save(user, {})
    assert new_event.valid?

    new_request = new_event.requests.first
    #
    #  num_allocated makes use of the cached commitment count in the
    #  request record.  Make sure that matches reality with a forced
    #  d/b access to get the real count.
    #
    assert_equal new_request.commitments.count, new_request.num_allocated, "Checking cached count"
    assert_equal 0, new_request.num_allocated
    assert_equal 2, new_request.num_outstanding

    assert new_event.commitments.empty?
  end

  test "make_to_match brings over new commitments" do
    event = FactoryBot.create(:event)
    staff1 = FactoryBot.create(:staff)
    staff2 = FactoryBot.create(:staff)
    user = FactoryBot.create(:user)
    commitment1 = event.commitments.create({
      element: staff1.element
    })
    assert commitment1.valid?
    new_event = event.clone_and_save(user, {})
    assert new_event.valid?
    assert_equal 1, new_event.commitments.size
    assert_not_equal event.commitments.first, new_event.commitments.first
    commitment2 = event.commitments.create({
      element: staff2.element
    })
    assert commitment2.valid?
    assert_equal 2, event.commitments.size, "Commitments on original event"
    assert_equal 1, new_event.commitments.size
    new_event.make_to_match(user, event)
    assert_equal 2, new_event.commitments.size, "Commitments on new event"
  end

  test "make_to_match brings over new requests" do
    event = FactoryBot.create(:event)
    resourcegroup1 = FactoryBot.create(:resourcegroup)
    resourcegroup2 = FactoryBot.create(:resourcegroup)
    user = FactoryBot.create(:user)
    request1 = event.requests.create({
      element: resourcegroup1.element,
      quantity: 1
    })
    assert request1.valid?
    #
    #    This reload shouldn't be necessary, but there appears to be
    #    a bug in ActiveRecord which makes the request appear twice
    #    in the array.  The count is 1, but the size is 2 and if you
    #    iterate through then the same record appears twice.
    #
    event.reload
    new_event = event.clone_and_save(user, {})
    assert new_event.valid?
    request2 = event.requests.create({
      element: resourcegroup2.element,
      quantity: 1
    })
    assert_equal 2, event.requests.size, "Requests on original event"
    assert_equal 1, new_event.requests.size
    new_event.make_to_match(user, event)
    assert_equal 2, new_event.requests.size, "Requests on new event"
  end

  test "make_to_match does not copy commitment filling request" do
    event = FactoryBot.create(:event)
    resourcegroup1 = FactoryBot.create(:resourcegroup)
    resource1 = FactoryBot.create(:service)
    user = FactoryBot.create(:user)
    request1 = event.requests.create({
      element: resourcegroup1.element,
      quantity: 2
    })
    assert request1.valid?
    #
    #    This reload shouldn't be necessary, but there appears to be
    #    a bug in ActiveRecord which makes the request appear twice
    #    in the array.  The count is 1, but the size is 2 and if you
    #    iterate through then the same record appears twice.
    #
    event.reload
    new_event = event.clone_and_save(user, {})
    assert new_event.valid?

    request1.fulfill(resource1.element)
    assert_equal 1, request1.num_allocated, "Num allocated"
    assert_equal 1, request1.num_outstanding, "Num outstanding"

    new_event.make_to_match(user, event)

    new_request = new_event.requests.first
    assert_equal 0, new_request.num_allocated
    assert_equal 2, new_request.num_outstanding

    assert new_event.commitments.empty?
  end

  #
  #  Tests relating to journaling.  Notice that we do not test what
  #  kind of entry has been created or what it contains - that's up
  #  to the model tests for the Journal model.  What we're testing
  #  here is that the shims in the Event model work.
  #

  test "no journal by default" do
    assert_nil @efj.journal
  end

  test "can explicitly add journal" do
    @efj.ensure_journal
    assert_not_nil @efj.journal
  end

  test "can journal event created" do
    @efj.journal_event_created(@user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal event updated" do
    #
    #  Here we do have to make an actual change to the event, otherwise
    #  nothing will be journaled.
    #
    #  The journal must exist before the change is made too.
    #
    @efj.ensure_journal
    @efj.body = "Modified body text"
    @efj.ends_at = @efj.ends_at + 1.hour
    @efj.journal_event_updated(@user)
    assert_not_nil @efj.journal
    #
    #  Two things changed, so two journal entries.
    #
    assert_equal 2, @efj.journal.journal_entries.count
  end

  test "can journal event destroyed" do
    @efj.journal_event_destroyed(@user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal commitment added" do
    @efj.journal_commitment_added(@commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal commitment removed" do
    @efj.journal_commitment_removed(@commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal commitment approved" do
    @efj.journal_commitment_approved(@commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal commitment rejected" do
    @efj.journal_commitment_rejected(@commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal commitment noted" do
    @efj.journal_commitment_noted(@commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal commitment reset" do
    @efj.journal_commitment_reset(@commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal note added" do
    @efj.journal_note_added(@note, @commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal note updated" do
    @efj.journal_note_updated(@note, @commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal form completed" do
    @efj.journal_form_completed(@ufr, @commitment, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal repeated from" do
    @efj.journal_repeated_from(@user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request created" do
    @efj.journal_resource_request_created(@request, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request destroyed" do
    @efj.journal_resource_request_destroyed(@request, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request incremented" do
    @efj.journal_resource_request_incremented(@request, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request decremented" do
    @efj.journal_resource_request_decremented(@request, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request adjusted" do
    @efj.journal_resource_request_adjusted(@request, 2, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request allocated" do
    @efj.journal_resource_request_allocated(@request, @user, @resource.element)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request deallocated" do
    @efj.journal_resource_request_deallocated(
      @request, @user, @resource.element)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  test "can journal resource request reconfirmed" do
    @efj.journal_resource_request_reconfirmed(@request, @user)
    assert_not_nil @efj.journal
    assert_equal 1, @efj.journal.journal_entries.count
  end

  #
  #  Leave this test at the end.  It needs investigating at some point.
  #
  #  Now commented out because the bug seems to have been fixed in Rails
  #  5.  This test now fails - as it should.
  #
#  test "odd bug in ActiveRecord" do
    #
    #  Note, we're testing that the bug *does* exist.
    #
    #  This test is left here for documentary purposes.  So far I've
    #  failed to spot why this happens with requests but not with commitments.
    #
    #  I have observed this kind of behaviour before but failed to
    #  record the exact circumstances which produced hit.  Hence
    #  I'm recording it here, so I can compare the next time I come
    #  across it.
    #
#    event = FactoryBot.create(:event)
#    resourcegroup = FactoryBot.create(:resourcegroup)
#    user = FactoryBot.create(:user)
#    request = event.requests.create({
#      element: resourcegroup.element,
#      quantity: 1
#    })
#    assert request.valid?
#    assert_equal 2, event.requests.size, "requests.size"
#    assert_equal 1, event.requests.count, "requests.count"
#    count = 0
#    event.requests.each do |request|
#      count += 1
#    end
#    assert_equal 2, count, "Count of requests"
    #
    #  And try it with commitments
    #
#    staff = FactoryBot.create(:staff)
#    commitment = event.commitments.create({
#      element: staff.element
#    })
#    assert commitment.valid?
#    assert_equal 1, event.commitments.count, "Size of commitments"
#    count = 0
#    event.commitments.each do |commitment|
#      count += 1
#    end
#    assert_equal 1, count, "Count of commitments"
#  end

end
