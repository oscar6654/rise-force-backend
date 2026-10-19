class AiBrief < ApplicationRecord
  belongs_to :subject, polymorphic: true

  validates :kind, :period_date, presence: true

  # Today's (or a given day's) brief record for a subject+kind, or nil.
  def self.record_for(subject, kind, on: Date.current)
    where(subject: subject, kind: kind, period_date: on).order(updated_at: :desc).first
  end

  # Just the body (back-compat).
  def self.current(subject, kind, on: Date.current)
    record_for(subject, kind, on: on)&.body
  end

  # Upsert the day's brief (keeps one row per subject/kind/day).
  def self.store(subject, kind, body, model:, on: Date.current)
    find_or_initialize_by(subject: subject, kind: kind, period_date: on)
      .update!(body: body, model: model)
  end
end
