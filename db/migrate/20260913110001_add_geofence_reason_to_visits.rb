class AddGeofenceReasonToVisits < ActiveRecord::Migration[8.1]
  # The app already captures why a seller checked in outside the geofence
  # (soft mode) but the backend was dropping it. Persist it for the audit trail.
  def change
    add_column :visits, :geofence_reason, :string
  end
end
