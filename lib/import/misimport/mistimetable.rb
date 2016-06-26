class MIS_PeriodTime
  attr_reader :starts_at, :ends_at, :ls_starts_at, :ls_ends_at

  #
  #  The MIS is responsible for providing the above, in a textual
  #  form like this:
  #
  #  "09:03"
  #  "12:27"
  #
  #  etc.  Note that they are always 5 characters long.
  #
end

class MIS_ScheduleEntry

  attr_reader :dbrecord, :groups, :staff, :rooms

  #
  #  The job of this function is to ensure that an appropriate
  #  matching database entry exists with the right time.  We either
  #  find an existing one on the indicated date (adjusting the time
  #  if necessary) or create one.  Either way, we end up with an
  #  @dbrecord instance variable pointing to it.
  #
  #  It should also do things like lesson suspensions, checking
  #  categories, lesson name etc (see importsb.rb for missing functionality)
  #  but that is still to be added.
  #
  def ensure_db(date, event_source)
    created_count = 0
    amended_count = 0
    period_time = self.period_time
    starts_at = Time.zone.parse("#{date.to_s} #{period_time.starts_at}")
    ends_at   = Time.zone.parse("#{date.to_s} #{period_time.ends_at}")
    @dbrecord =
      Event.events_on(
        date,          # Start date
        nil,           # End date
        nil,           # Categories
        @event_source, # Event source
        nil,           # Resource
        nil,           # Owner
        true           # And non-existent
      ).source_hash(self.source_hash).take
    if @dbrecord
      #
      #  Just need to make sure the time is right.
      #
      changed = false
      if @dbrecord.starts_at != starts_at
        @dbrecord.starts_at = starts_at
        changed = true
      end
      if @dbrecord.ends_at != ends_at
        @dbrecord.ends_at = ends_at
        changed = true
      end
      if changed
        if @dbrecord.save
          #
          #  Incremement counter
          #
          @dbrecord.reload
          amended_count += 1
        else
          puts "Failed to save amended event record."
        end
      end
    else
      event = Event.new
      event.body          = self.body_text
      event.eventcategory = self.eventcategory
      event.eventsource   = event_source
      event.starts_at     = starts_at
      event.ends_at       = ends_at
      event.approximate   = false
      event.non_existent  = self.suspended_on?(date)
      event.private       = false
      event.all_day       = false
      event.compound      = true
      event.source_hash   = self.source_hash
      if event.save
        event.reload
        @dbrecord = event
        created_count += 1
      else
        puts "Failed to save event #{event.body}"
        event.errors.messages.each do |key, msgs|
          puts "#{key}: #{msgs.join(",")}"
        end
      end
    end
    [created_count, amended_count]
  end

  def ensure_resources
    raise "Can't ensure resources without a dbrecord." unless @dbrecord
    changed = false
    resources_added_count = 0
    resources_removed_count = 0
    #
    #  We use our d/b element ids
    #  as unique identifiers.
    #
    mis_element_ids =
      (self.groups.collect {|g| g.element_id} +
       self.staff.collect {|s| s.element_id} +
       self.rooms.collect {|r| r.element_id}).compact
    db_element_ids = @dbrecord.commitments.collect {|c| c.element_id}
    db_only = db_element_ids - mis_element_ids
    mis_only = mis_element_ids - db_element_ids
    mis_only.each do |misid|
      c = Commitment.new
      c.event      = @dbrecord
      c.element_id = misid
      c.save
      resources_added_count += 1
    end
    @dbrecord.reload
    if db_only.size > 0
      @dbrecord.commitments.each do |c|
        if db_only.include?(c.element_id) && !c.covering
          c.destroy
          resources_removed_count += 1
        end
      end
    end
    [resources_added_count, resources_removed_count]
  end

end

class MIS_Schedule
end

class MIS_Timetable
end
