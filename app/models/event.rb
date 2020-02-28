class Event < ApplicationRecord
  before_save :complete_days_to_week_start
  APPOINTMENT_INTERVAL = 30.minutes
  AVAILABILITY_WINDOW = 7.days

  def self.availabilities(start_date)
    [].tap do |availabilities|
      concerned_events = Event
        .where("starts_at <= ?", start_date.end_of_day + AVAILABILITY_WINDOW)
        .group_by(&:days_to_week)
      start_days = start_date.days_to_week_start
      (0...AVAILABILITY_WINDOW / 1.day).each do |day_index|
        current_date = start_date + day_index
        current_days_to_week = (start_days + day_index) % 7
        events = concerned_events[current_days_to_week]
        availabilities << {
          date: current_date.to_date,
          slots: time_slots_from_mask(availabilities_for(current_date, events))
        }
      end
    end
  end

  def self.time_slots_from_mask(mask)
    [].tap do |slots|
      left_padding_time = (1.day / APPOINTMENT_INTERVAL - mask.bit_length) * APPOINTMENT_INTERVAL
      mask.to_s(2).each_char.with_index do |char, index|
        slot_time = left_padding_time + index * APPOINTMENT_INTERVAL
        slot_hour = slot_time / 60.minutes
        slot_min = (slot_time - slot_hour * 60.minutes) / 1.minute
        if char == '1'
          slots << "#{slot_hour}:#{slot_min.to_s.rjust(2, '0')}"
        end
      end
    end
  end

  def self.availabilities_for(current_date, events)
    opening_events = events&.find_all do |event|
      event.kind == 'opening' && (event.weekly_recurring || event.starts_at.to_date == current_date)
    end
    return 0 if opening_events.blank?
    appointment_events = events&.find_all { |event| event.kind == 'appointment' && event.starts_at.to_date == current_date }
    opening_mask = 0
    opening_events&.each do |event|
      opening_mask = opening_mask | event.send(:mask_for_time_slots)
    end
    appointment_mask = 0
    appointment_events&.each do |event|
      appointment_mask = appointment_mask | event.send(:mask_for_time_slots)
    end
    opening_mask & appointment_mask ^ opening_mask
  end

  private_class_method :availabilities_for, :time_slots_from_mask

  private

  def complete_days_to_week_start
    self.days_to_week = self.starts_at.days_to_week_start
  end

  def mask_for_time_slots
    offset = (ends_at.next_day.beginning_of_day - ends_at) / APPOINTMENT_INTERVAL
    slots_number = (ends_at - starts_at) / APPOINTMENT_INTERVAL
    ('1' * slots_number).to_i(2) << offset
  end
end