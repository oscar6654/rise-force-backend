require "rails_helper"

RSpec.describe "Promo.refresh_statuses!" do
  def promo(code, status, from, to)
    Promo.create!(code: code, name: code, mechanic_type: :discount_percent, status: status,
                  start_date: from, end_date: to)
  end

  it "flips stored status to match the date window, leaving cancelled alone" do
    ended = promo("E", :active,    Date.current - 40, Date.current - 10) # window passed
    live  = promo("L", :active,    Date.current - 5,  Date.current + 5)  # in window
    sched = promo("S", :active,    Date.current + 5,  Date.current + 10) # not started
    canc  = promo("C", :cancelled, Date.current - 40, Date.current - 10) # terminal

    Promo.refresh_statuses!

    expect(ended.reload.status).to eq("ended")
    expect(live.reload.status).to eq("active")
    expect(sched.reload.status).to eq("scheduled")
    expect(canc.reload.status).to eq("cancelled") # never un-cancelled
  end
end
