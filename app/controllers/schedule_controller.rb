# Xronos Scheduler - structured scheduling program.
# Copyright (C) 2009-2014 John Winters
# See COPYING and LICENCE in the root directory of the application
# for more information.

class ScheduleController < ApplicationController
  include DisplaySettings

  layout 'schedule'

  #
  #  This is much like an Event, but carries more display information.
  #
  class ScheduleEvent

    #
    #  A bit of messing about is needed to generate a constant hash with
    #  a default value.
    #
    #  I got this from a blog posting and it doesn't actually work.
    #  it returns a string, not a hash.  It also appears to be quite
    #  unnecessary, since the straightforward approach works without
    #  even producing a warning.
    #
    #KNOWN_COLOUR_NAMES = lambda do
    #  known_colour_names = {
    #    "red"   => "#FF0000",
    #    "pink"  => "#FFC0CB",
    #    "green" => "#008000"
    #  }.default = "#000000"
    #  known_colour_names
    #end.call
    #
    KNOWN_COLOUR_NAMES = {
      "red"   => "#FF0000",
      "pink"  => "#FFC0CB",
      "green" => "#008000"
    }
    KNOWN_COLOUR_NAMES.default = "#000000"

    #
    #  Passed a colour, produces a more greyed out version of the same
    #  colour.  Lighter, and with less colour density, but still
    #  clearly related.
    #
    def washed_out(colour)
      if colour[0] != "#"
        colour = KNOWN_COLOUR_NAMES[colour]
      end
      red_bit   = colour[1,2].hex
      green_bit = colour[3,2].hex
      blue_bit  = colour[5,2].hex
      #
      #  Each bit is half way between its original shade and full blast.
      #
      red_bit   = (255 - (255 - red_bit)   / 2)
      green_bit = (255 - (255 - green_bit) / 2)
      blue_bit  = (255 - (255 - blue_bit)  / 2)
      "##{
           sprintf("%02x", red_bit)
         }#{
           sprintf("%02x", green_bit)
         }#{
           sprintf("%02x", blue_bit)
         }"
    end

    def redden(colour)
      "#ff7070"
    end

    def initialize(event,
                   via_element,
                   current_user = nil,
                   colour = nil,
                   mine = false)
      @event  = event
      if colour
        @colour = colour
        #
        #  If this is an event covered by the current user, *and* we
        #  are selecting it by the current user's own element, then we
        #  change the colour to red.  Likewise for invigilations.
        #
        if mine &&
           current_user &&
           current_user.known? &&
           (event.covered_by?(current_user.own_element) ||
            event.eventcategory_id == Event.invigilation_category.id)
          @colour = "red"
        end
      elsif event.eventcategory_id == Event.weekletter_category.id
        @colour = "pink"
#        @colour = "#212D48"  # Blue of the title bar - good one.
#        @colour = "#663d52"  # Darkish pink
      else
        @colour = "green"
#        @colour = "#4068b2"  # Blue very like "myself" - good one.
#        @colour = "#7094ff"
#        @colour = "#3366ff"
#        @colour = "#00476b"  # Distinguised blue
      end
      #
      #  Conditions for washing out the colour.
      #
      #  1) The event is non-existent.
      #  2) The event is incomplete *and* we aren't accessing it via
      #     an element which we own.  If we are accessing it via an
      #     element which we own, then we grey out only if the corresponding
      #     commitment is still tentative.
      #
      if event.non_existent
        @colour = washed_out(@colour)
      else
        unless event.complete
          #
          #  Users who aren't logged in don't get to know nuances
          #  about whether events are complete or not.
          #
          if current_user && current_user.known?
            if via_element
              #
              #  And only those with a special interest get to know
              #  about rejections.
              #
              if current_user.owns?(via_element) ||
                 current_user.admin ||
                 current_user.id == event.owner_id
                #
                #  Has the commitment been approved?
                #
                c = Commitment.find_by(element_id: via_element.id,
                                       event_id: event.id)
                if c
                  if c.tentative
                    if c.rejected
                      @colour = redden(@colour)
                    else
                      @colour = washed_out(@colour)
                    end
                  end
                else
                  #
                  #  Odd - can't find the corresponding commitment.
                  #  Err on the side of caution and wash it out.
                  #
                  @colour = washed_out(@colour)
                end
              else
                @colour = washed_out(@colour)
              end
            else
              #
              #  We're trying to look at the event *not* via
              #  a particular element.  This means we own it,
              #  are listed as the organiser, or that it's a
              #  breakthrough event of some sort.
              #
              #  Given that it's not complete, wash it out.
              #
              @colour = washed_out(@colour)
            end
          end
        end
      end
#      Rails.logger.debug("Current user is #{current_user.email}")
      #
      #  Note that our idea of editable is slightly different from
      #  FullCalendar's.  If I set editable on the event data, then
      #  FullCalendar will let us drag it around - i.e. change the time.
      #  This corresponds to our idea of being retimeable.
      #
      @editable = current_user ? current_user.can_retime?(event) : false
      #
      #  We used to let the user go straight into editing an event.  Now
      #  we display it first, because there's so much information.
      #
      #@edit_dialogue = current_user ? current_user.can_edit?(event) : false
      @edit_dialogue = false
      #
      #  We are slightly coy about displaying clash information.  Only
      #  those who would be able to see the details (i.e. staff) get
      #  to see the little icon.
      #
      @has_clashes = event.has_clashes && current_user && current_user.staff?
    end

    def as_json(options = {})
      {
        :id            => "#{@event.id}",
        :title         => @event.body,
        :start         => @event.starts_at_for_fc,
        :end           => @event.ends_at_for_fc,
        :allDay        => @event.all_day,
        :recurring     => false,
        :editable      => @editable,
        :edit_dialogue => @edit_dialogue,
        :color         => @colour,
        :has_clashes   => @has_clashes
      }
    end

  end

  def show
    if params[:date]
      #
      #  If the request specifies a date then we get a little tricky.
      #  We could just shove that date in the :last_start_date field
      #  in the session and then go on to display the page, but then
      #  the specified date would stay in the URL.  Instead we shove
      #  it there and then redirect to the root (which is us again)
      #  but it means that if the user later refreshes the page, he
      #  or she won't be sent back to this date.
      #
      session[:last_start_date] = Time.zone.parse(params[:date])
      #
      #  We also allow the possibility of specifying a particular
      #  concern belonging to the user which should be set to visible.
      #  This is to facilitate the approval of event requests.
      #
      concern_id = params[:concern_id]
      if concern_id
        #
        #  Possible we might get nonsense here - don't want to
        #  raise an error.  Calling just find() would raise an
        #  error if the concern id was invalid.
        #
        concern = Concern.find_by(id: concern_id)
        if concern && concern.user == current_user
          unless concern.visible
            concern.visible = true
            concern.save
          end
        end
      end
      redirect_to :root
    else
      #
      #  We should decide here what exactly gets shown in the way
      #  of columns, user information and concerns - *not* in the view.
      #
      if (current_user && current_user.known?) ||
         Property.public_ones.count > 1
        @show_lhs     = true
      else
        #
        #  Note that the key word here is "show".  The div containing
        #  a possible pseudo-concern will still be there (and so the
        #  corresponding events will still be fetched), but it will be
        #  hidden.
        #
        @show_lhs     = false
      end
      setvars_for_lhs(current_user)
      #
      #  Make space for creating a new concern.
      #
      @concern = Concern.new
      start_at = session[:last_start_date] || Time.zone.now
      @default_date = start_at.strftime("%Y-%m-%d")
      @show_jump = true
      respond_to do |format|
        format.html
      end
    end
  end

  def events
#    raise params.inspect
    start_date = Time.zone.parse(params[:start])
    end_date   = Time.zone.parse(params[:end]) - 1.day
    if current_user && current_user.known?
      concern_id = params[:cid].to_i
      if concern_id == 0
        #
        #  For this particular request, we make a note of the start
        #  date, in order to be able to return to it on a page refresh
        #  later.
        #
        session[:last_start_date] = start_date
        #
        #  We are being asked for the usual list of events for the
        #  current user.  These consist of:
        #
        #  * Events the user owns (i.e. he or she edited them in).
        #  * Events the user's element is listed as organising.
        #
        #  As an order of precedence, we classify the events in that order.
        #  Each event should appear only once, and in the category which
        #  is listed here first.
        #
        #
        watched_elements =
          current_user.concerns.visible.collect {|concern| concern.element}
        if current_user.show_owned
          my_owned_events =
            current_user.events_on(start_date,
                                   end_date,
                                   nil,
                                   nil,
                                   true)
          my_organised_events =
            Event.events_on(start_date,
                            end_date,
                            nil,
                            nil,
                            nil,
                            nil,
                            true,
                            current_user.own_element) - my_owned_events
          #
          #  Now I want to subtract from my owned events, the list of
          #  events involving elements which I am currently watching by
          #  another means.
          #
          #  Currently this is only going to work for direct involvement,
          #  not involvement via a group.
          #
          my_owned_events =
            my_owned_events.select { |e|
              !e.eventcategory.visible || !e.involves_any?(watched_elements)
            }
        else
          my_owned_events = []
          my_organised_events = []
        end
        schoolwide_events =
          Event.events_on(start_date,
                          end_date,
                          Eventcategory.schoolwide) -
                          (my_owned_events + my_organised_events)
        @schedule_events =
          my_owned_events.collect {|e|
            ScheduleEvent.new(e,
                              nil,
                              current_user,
                              current_user.colour_not_involved)
          } +
          my_organised_events.collect {|e|
            ScheduleEvent.new(e,
                              nil,
                              current_user,
                              current_user.colour_not_involved)
          } +
          schoolwide_events.collect {|e|
            ScheduleEvent.new(e,
                              nil,
                              current_user)
          }
      else
        #
        #  An explicit request for the events relating to a specified
        #  element.  Only allow it if the element is listed as being
        #  one of the current user's interests.  This is to stop users
        #  being able to hand-craft requests for information to which
        #  they might not be entitled.
        #
        concern =
          current_user.concerns.detect {|ci| ci.id == concern_id}
        if concern && concern.visible
          element = concern.element
          if element.entity.instance_of?(Property)
            #
            #  The .to_a forces the lambda to be evaluated now.  We don't
            #  want the database being queried again and again for the
            #  same answer.
            #
            event_categories = Eventcategory.not_schoolwide.visible.to_a
          else
            event_categories = Eventcategory.visible.to_a
          end
          #
          #  Deciding what events exactly to show needs specialist
          #  knowledge of the user, the concern, the commitment connecting
          #  element to event, and the event itself.  Delegate the task
          #  to the element model.
          #
          @schedule_events =
            element.display_events(start_date,
                                   end_date,
                                   event_categories,
                                   current_user,
                                   concern).collect {|e|
                      ScheduleEvent.new(e,
                                        element,
                                        current_user,
                                        concern.colour,
                                        concern.equality)
                    }
        else
          @schedule_events = []
        end
      end
    else
      #
      #  We expect to be passed a *fake* concern ID - starts with E
      #  followed by a number.  It must lead us to the element of a
      #  public property.
      #
      #  We also might be passed no ID at all, in which case we
      #  return just the breakthrough events.
      #
      @schedule_events = []
      fake_id = params[:cid]
      if fake_id =~ /^E\d+$/
        element_id = fake_id[1..-1].to_i
        element = Element.find_by(id: element_id)
        if element &&
          element.entity_type == "Property" &&
          element.entity.make_public
          #
          #  This looks like a really weird test, but I want to treat
          #  the absence of the relevant key as being equivalent to true.
          #  Absence will return nil.  Only an actual value of false
          #  should suppress the events.
          #
          if session[fake_id] != false
            #
            #  Now, in picking the events to show I want to filter out
            #  any where the category means they would break through
            #  anyway.  Basically these are key dates and week letters.
            #
            @schedule_events +=
              element.events_on(start_date,
                                end_date,
                                Eventcategory.not_schoolwide.visible.to_a).collect {|e|
                ScheduleEvent.new(e, nil, nil, element.preferred_colour)
              }
          end
        end
      elsif fake_id.blank?
        session[:last_start_date] = start_date
        @schedule_events =
         Event.events_on(
           start_date,
           end_date,
           Eventcategory.schoolwide.visible.to_a).collect {|e|
             ScheduleEvent.new(e, nil, nil)}
      end
      #
      #
      #  People who aren't logged on, or who we don't recognise, just
      #  get to see the public calendars.
      #
#      session[:last_start_date] = start_date
#      @schedule_events = []
#      public_properties = Property.where(make_public: true)
#      public_properties.each do |pp|
#        calendar_element = pp.element
#        @schedule_events +=
#          calendar_element.events_on(start_date, end_date).collect {|e|
#            ScheduleEvent.new(e, nil, nil, calendar_element.preferred_colour)
#          }
#      end
    end
    begin
      respond_to do |format|
        format.json { render json: @schedule_events }
      end
    end
  end

  private

  #
  #  Currently the only two actions which we offer are show and events,
  #  but list them explicitly in order to fail safe in the case of future
  #  expansion.
  #
  def authorized?(action = action_name, resource = nil)
    (logged_in? && current_user.admin) ||
    action == 'show' || action == 'events'
  end

end
