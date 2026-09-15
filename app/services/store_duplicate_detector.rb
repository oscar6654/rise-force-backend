# Flags a StoreRegistration as a possible duplicate of an existing store using
# (a) trigram name similarity (pg_trgm) and (b) geographic proximity via a
# bounding-box + Haversine prefilter. Returns the best candidate + a score and
# human-readable flags. Non-destructive — the reviewer confirms.
class StoreDuplicateDetector
  NAME_SIMILARITY_THRESHOLD = 0.4
  PROXIMITY_METERS = 75

  Result = Struct.new(:store, :score, :flags, keyword_init: true)

  # Great-circle distance in metres (shared with visit GPS-mismatch checks).
  def self.distance_m(lat1, lon1, lat2, lon2)
    r = 6_371_000.0
    dlat = (lat2 - lat1) * Math::PI / 180
    dlon = (lon2 - lon1) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * Math.sin(dlon / 2)**2
    r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  def initialize(registration)
    @reg = registration
  end

  def detect
    flags = []
    candidates = Store.where(branch_id: @reg.branch_id).where.not(status: :rejected)

    # Name similarity (pg_trgm). Guard when name is blank.
    name_match = nil
    if @reg.name.present?
      name_match = candidates
                   .select("stores.*, similarity(name, #{Store.connection.quote(@reg.name)}) AS sim")
                   .where("similarity(name, ?) > ?", @reg.name, NAME_SIMILARITY_THRESHOLD)
                   .order("sim DESC")
                   .first
      flags << "name~#{(name_match.sim.to_f * 100).round}%" if name_match
    end

    # Geographic proximity (only if we have coordinates).
    geo_match = nearest_within(candidates, PROXIMITY_METERS)
    flags << "within #{PROXIMITY_METERS}m of an existing store" if geo_match

    # Exact contact-number match.
    if @reg.contact_number.present?
      phone_match = candidates.find_by(contact_number: @reg.contact_number)
      flags << "same contact number" if phone_match
    end

    best = name_match || geo_match || phone_match
    score = flags.size # simple confidence proxy
    Result.new(store: best, score: score, flags: flags)
  end

  # Persist detection results onto the registration.
  def detect!
    result = detect
    @reg.update!(
      duplicate_of_store_id: result.store&.id,
      duplicate_score: result.score,
      duplicate_flags: result.flags
    )
    result
  end

  private

  def nearest_within(candidates, meters)
    return nil if @reg.latitude.blank? || @reg.longitude.blank?

    lat = @reg.latitude.to_f
    lng = @reg.longitude.to_f
    delta = meters / 111_000.0 # ~metres per degree

    candidates
      .where.not(latitude: nil, longitude: nil)
      .where(latitude: (lat - delta)..(lat + delta), longitude: (lng - delta)..(lng + delta))
      .min_by { |s| haversine(lat, lng, s.latitude.to_f, s.longitude.to_f) }
      .then { |s| s if s && haversine(lat, lng, s.latitude.to_f, s.longitude.to_f) <= meters }
  end

  def haversine(lat1, lon1, lat2, lon2)
    self.class.distance_m(lat1, lon1, lat2, lon2)
  end
end
