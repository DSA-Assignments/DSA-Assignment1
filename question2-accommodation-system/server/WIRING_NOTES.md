# Wiring guest_logic.bal into the gRPC service

1. Run `bal build` on `../proto/rental.proto` (or generate via the Ballerina
   gRPC tool) to produce the generated service skeleton + message records.
2. In the generated `RentalService` implementation, each guest-side remote
   method should call the matching function here:
   - `listAvailableProperties` → `listAvailableProperties(req.location, req.maxPrice)`, then stream the array back
   - `searchProperty` → `searchProperty(req.propertyId)`
   - `bookProperty` → `bookProperty(req.propertyId, req.guestId, req.checkIn, req.checkOut)`
   - `confirmBooking` → `confirmBooking(req.propertyId)` — **note:** the proto
     currently sends `PropertyId` to `confirmBooking`, but the logic here
     confirms by `guestId` (matching "confirm the calling guest's cart").
     Flag this with Person 5/6 — you may need to add `guestId` to the
     `confirmBooking` request message, or look up the guest from the
     property's cart entry.
3. `propertyTable` is only ever *read* by this file. Person 6's
   `addProperty` / `updateProperty` / `removeProperty` / `createUsers`
   implementations need to write to the same `propertyTable` in `types.bal`
   for guest-side logic to see real data — until that's merged, you can
   manually seed `propertyTable` in a test file to demo guest-side flows.
