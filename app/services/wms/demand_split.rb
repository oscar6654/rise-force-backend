module Wms
  # Shared demand → fulfillment-line builder. Given a product and a quantity in
  # canonical PIECES, it adds the right lines to a fulfillment order, splitting
  # full cases (picked from case bins) from the sub-case remainder (loose, from
  # the piece zone) when the warehouse runs a piece-pick zone. Used by both the
  # SFA auto-flow (DemandFromOrder) and the manual dispatch CSV upload, so they
  # behave identically. The product carries the itemkey + case barcode; the exact
  # itemkey consumed is resolved by FIFO at allocation time.
  module DemandSplit
    module_function

    def add_line!(fo, product, pieces)
      pieces = pieces.to_i
      return if pieces <= 0

      per_case = product.pcs_per_case || 1
      if fo.warehouse.piece_pick_zone.present? && per_case > 1
        full  = (pieces / per_case) * per_case # whole cases, in pieces
        loose = pieces - full                  # sub-case remainder
        fo.fulfillment_lines.create!(product: product, qty_demanded: full,  uom: :pc, pack: :case)  if full.positive?
        fo.fulfillment_lines.create!(product: product, qty_demanded: loose, uom: :pc, pack: :loose) if loose.positive?
      elsif fo.warehouse.piece_pick_zone.present?
        # pcs_per_case == 1 → no case concept, everything is loose.
        fo.fulfillment_lines.create!(product: product, qty_demanded: pieces, uom: :pc, pack: :loose)
      else
        # No piece zone configured → one line, picked from any pickable bin.
        fo.fulfillment_lines.create!(product: product, qty_demanded: pieces, uom: :pc, pack: :case)
      end
    end
  end
end
