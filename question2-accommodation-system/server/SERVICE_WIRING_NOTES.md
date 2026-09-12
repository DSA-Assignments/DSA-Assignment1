# Service wiring — notes for the group

## What this adds

`server/service.bal` — the gRPC service that connects the generated
`RentalService` skeleton to the plain functions in `host_logic.bal` and
`guest_logic.bal`. Until this existed, both logic modules were complete but
unreachable: nothing called them.

All eight RPCs are wired:

| RPC | Style | Calls |
|---|---|---|
| `addProperty` | Simple | `host_logic:addProperty` |
| `updateProperty` | Simple | `host_logic:updateProperty` |
| `removeProperty` | Simple | `host_logic:removeProperty` |
| `createUsers` | **Client streaming** | `host_logic:registerUser` per message |
| `listAvailableProperties` | **Server streaming** | `guest_logic:listAvailableProperties` |
| `searchProperty` | Simple | `guest_logic:searchProperty` |
| `bookProperty` | Simple | `guest_logic:bookProperty` |
| `confirmBooking` | Simple | `guest_logic:confirmBooking` |

---

## Proto change required — please review

`WIRING_NOTES.md` flagged this and asked for a decision. Here it is, with
reasoning, so it can be accepted or overruled.

**The problem.** `bookingCart` in `types.bal` is keyed by guestId:

```ballerina
isolated map<BookingCartEntry> bookingCart = {}; // keyed by guestId
```

`guest_logic:confirmBooking` therefore takes a `guestId`. The proto was
sending `propertyId`, which cannot look up a cart entry. As it stood, these
two could not be wired together at all.

**The fix.** `ConfirmBookingRequest` carries guestId:

```proto
message ConfirmBookingRequest {
    string guestId = 1;
}
```

**Why this way round.** The alternative was re-keying `bookingCart` by
propertyId. Rejected for two reasons:

1. The brief says confirm_booking must "clear the Guest's temporary
   request" — the operation is scoped to a guest, not a property.
2. Keying by propertyId would stop one guest holding two pending requests
   for different properties, which is normal behaviour for a booking cart.

If anyone disagrees, the change is one line in the proto and one argument in
`service.bal` — easy to reverse.

---

## Generated names need checking

`bal grpc` has not been run in this environment, so the generated message
record names in `service.bal` are assumptions based on the RPC names in
`WIRING_NOTES.md`. After running:

```bash
cd server
bal grpc --input ../proto/rental.proto --output .
```

open `rental_pb.bal` and check these against what was actually generated:

- `AddPropertyRequest` / `AddPropertyResponse`
- `UpdatePropertyRequest` / `UpdatePropertyResponse`
- `RemovePropertyRequest` / `PropertyList`
- `UserProfileMessage` / `UserCreationSummary`
- `ListAvailableRequest`
- `SearchPropertyRequest` / `SearchPropertyResponse`
- `BookPropertyRequest` / `BookPropertyResponse`
- `ConfirmBookingRequest` / `ConfirmBookingResponse`
- `ProtoPropertyCaller` (the server-streaming caller)

**One likely collision.** If the proto message is called `Property`, the
generated record will clash with our internal `Property` in `types.bal`.
Simplest fix is renaming the proto message to `PropertyMessage` and
regenerating. `service.bal` refers to it as `ProtoProperty` with a comment
marking the spot; `toProtoProperty()` is the only function that touches those
fields, so a rename is a single-place change.

---

## Three things worth a look (not fixed here — not my files)

**1. `daysBetween` returns 1 on an unparseable date**

```ballerina
if checkInUtc is error || checkOutUtc is error {
    return 1; // fallback so a bad date never crashes the price calc
}
```

Silently charging one night is arguably worse than rejecting the booking.
Dates are validated in `bookProperty` (`checkOut <= checkIn`), so by confirm
time they should already be sound — but a malformed date like `"2026-13-45"`
passes that string comparison and reaches here.

**2. No date-overlap checking**

`confirmBooking` sets `status = "BOOKED"`, which blocks the property
entirely rather than just the booked dates. The brief asks the server to
"verify the property is still available for the requested dates (ensure no
date overlaps)". As written, a second guest cannot book *different* dates on
the same property.

Fixing properly would mean storing confirmed date ranges per property and
testing `aIn < bOut && bIn < aOut` (half-open, so one guest can check in the
day another checks out). Depends how strictly the lecturer reads that line.

**3. One cart per guest**

`bookingCart` keyed by guestId means a second `bookProperty` call silently
overwrites the first pending request. Probably fine for the demo, worth
knowing during it.
