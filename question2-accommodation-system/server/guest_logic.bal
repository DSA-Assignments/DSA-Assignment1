import ballerina/time;

// Task 7: Guest-side server logic.
//
// These are written as plain functions rather than methods on the generated
// gRPC service object, since the generated service skeleton doesn't exist
// until someone runs `bal build` against rental.proto (needs the Ballerina
// gRPC tool, which isn't available in this environment). Once the skeleton
// is generated, call these functions from inside the matching remote method
// — e.g. the generated `listAvailableProperties` method should just do
// `return listAvailableProperties(req.location, req.maxPrice);` and stream
// the result.

// ---- list_available_properties (server-streaming) ----
public isolated function listAvailableProperties(string? location, decimal? maxPrice) returns Property[] {
    lock {
        return from Property p in propertyTable
            where p.status == "AVAILABLE"
            where location is () || location == "" || p.location == location
            where maxPrice is () || p.pricePerNight <= maxPrice
            select p.clone();
    }
}

// ---- search_property ----
public type SearchOutcome record {|
    boolean available;
    Property? property;
    string status; // FOUND or NOT_AVAILABLE
|};

public isolated function searchProperty(string propertyId) returns SearchOutcome {
    lock {
        if propertyTable.hasKey(propertyId) {
            return { available: true, property: propertyTable.get(propertyId).clone(), status: "FOUND" };
        }
    }
    return { available: false, property: (), status: "NOT_AVAILABLE" };
}

// ---- book_property ----
public type BookingOutcome record {|
    boolean accepted;
    string message;
|};

public isolated function bookProperty(string propertyId, string guestId, string checkIn, string checkOut) returns BookingOutcome {
    lock {
        if !propertyTable.hasKey(propertyId) {
            return { accepted: false, message: "Property not found." };
        }
        Property p = propertyTable.get(propertyId);
        if p.status != "AVAILABLE" {
            return { accepted: false, message: "Property is not available." };
        }
        if checkOut <= checkIn {
            return { accepted: false, message: "Check-out date must be after check-in date." };
        }
        bookingCart[guestId] = { propertyId, guestId, checkIn, checkOut };
    }
    return { accepted: true, message: "Added to booking cart. Call confirmBooking to finalize." };
}

// ---- confirm_booking ----
public type ConfirmationOutcome record {|
    boolean confirmed;
    decimal totalCost;
    string message;
|};

public isolated function confirmBooking(string guestId) returns ConfirmationOutcome {
    lock {
        if !bookingCart.hasKey(guestId) {
            return { confirmed: false, totalCost: 0d, message: "No pending booking for this guest." };
        }
        BookingCartEntry entry = bookingCart.get(guestId);

        if !propertyTable.hasKey(entry.propertyId) {
            _ = bookingCart.remove(guestId);
            return { confirmed: false, totalCost: 0d, message: "Property no longer exists." };
        }

        Property p = propertyTable.get(entry.propertyId);
        if p.status != "AVAILABLE" {
            _ = bookingCart.remove(guestId);
            return { confirmed: false, totalCost: 0d, message: "Property is no longer available for those dates." };
        }

        int nights = daysBetween(entry.checkIn, entry.checkOut);
        decimal totalCost = p.pricePerNight * <decimal>nights;

        p.status = "BOOKED";
        propertyTable.put(p);
        _ = bookingCart.remove(guestId);

        return { confirmed: true, totalCost, message: "Booking confirmed." };
    }
}

isolated function daysBetween(string checkInDate, string checkOutDate) returns int {
    time:Utc|error checkInUtc = time:utcFromString(checkInDate + "T00:00:00.00Z");
    time:Utc|error checkOutUtc = time:utcFromString(checkOutDate + "T00:00:00.00Z");
    if checkInUtc is error || checkOutUtc is error {
        return 1; // fallback so a bad date never crashes the price calc
    }
    time:Seconds diff = time:utcDiffSeconds(checkOutUtc, checkInUtc);
    return <int>(diff / 86400d);
}
