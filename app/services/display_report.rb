# Matches display TARGET lines (from the xlsx base file) against execution
# EVIDENCE (photos from the CSV result file) for a campaign, scoped to a set of
# stores. A line is executed when ≥1 evidence photo matches on
# store + promotion + category (+ brand, when the target names one) AND the
# evidence's own [from,to] overlaps the campaign window. All matching photos are
# returned (a promo can repeat), newest-taken last.
class DisplayReport
  Photo = Struct.new(:image_url, :taken_on, :activity_type, keyword_init: true)
  Line  = Struct.new(:target_id, :promotion_name, :category, :brand, :executed, :photos, keyword_init: true)

  def initialize(campaign, store_ids: nil)
    @campaign = campaign
    @store_ids = store_ids
  end

  # => { store_id => { lines: [Line...], must:, done:, missing: } }
  # Only stores that actually have target lines appear.
  def by_store
    ev_by_key = Hash.new { |h, k| h[k] = [] }
    scoped(@campaign.display_evidences)
      .overlapping(@campaign.period_from, @campaign.period_to)
      .find_each { |e| ev_by_key[key(e.store_id, e.promotion_name, e.category)] << e }

    out = Hash.new { |h, k| h[k] = { lines: [], must: 0, done: 0 } }
    scoped(@campaign.display_targets).find_each do |t|
      group = ev_by_key[key(t.store_id, t.promotion_name, t.category)]
      matches = if t.brand.present?
                  tb = DisplayCampaign.norm(t.brand)
                  group.select { |e| DisplayCampaign.norm(e.brand) == tb }
                else
                  group
                end
      photos = matches
               .sort_by { |e| e.photo_taken_at || Date.new(1900) }
               .map { |e| Photo.new(image_url: e.image_url, taken_on: e.photo_taken_at, activity_type: e.activity_type) }
      st = out[t.store_id]
      st[:lines] << Line.new(target_id: t.id, promotion_name: t.promotion_name, category: t.category,
                             brand: t.brand, executed: photos.any?, photos: photos)
      st[:must] += 1
      st[:done] += 1 if photos.any?
    end
    out.each_value { |v| v[:missing] = v[:must] - v[:done] }
    out
  end

  private

  # Only stores in our master (store_id present) and, if given, the scope set.
  def scoped(rel)
    rel = rel.where.not(store_id: nil)
    rel = rel.where(store_id: @store_ids) if @store_ids
    rel
  end

  def key(store_id, promo, category)
    [store_id, DisplayCampaign.norm(promo), DisplayCampaign.norm(category)]
  end
end
