// service.bal
// Ministry of Tourism - Rental Accommodation System
// gRPC server implementation.
//
// Generate the stub first:
//     bal grpc --input rental.proto --output .
// That produces rental_pb.bal containing the generated message records and
// the RentalServiceServer listener types referenced below.

import ballerina/grpc;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

// ---------------------------------------------------------------------------
// In-memory data stores (concurrent-safe via `isolated` + lock)
// ---------------------------------------------------------------------------

isolated map<Property> propertyStore = {};
isolated map<User> userStore = {};
isolated map<Booking> bookingStore = {};

// Temporary booking cart: cart_id -> pending Booking.
isolated map<Booking> cartStore = {};

// Confirmed date ranges per property, used for overlap checking.
type DateRange record {|
    string checkIn;
    string checkOut;
|};

isolated map<DateRange[]> reservedDates = {};

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

// Counts nights between two ISO dates. Returns an error if the range is invalid.
isolated function nightsBetween(string checkIn, string checkOut) returns int|error {
    time:Utc inUtc = check time:utcFromString(checkIn + "T00:00:00Z");
    time:Utc outUtc = check time:utcFromString(checkOut + "T00:00:00Z");

    decimal diffSeconds = time:utcDiffSeconds(outUtc, inUtc);
    if diffSeconds <= 0d {
        return error("Check-out date must be after the check-in date.");
    }
    return <int>(diffSeconds / 86400d);
}

// True if two date ranges overlap. Ranges are half-open: [checkIn, checkOut).
isolated function overlaps(string aIn, string aOut, string bIn, string bOut)
        returns boolean {
    // ISO yyyy-MM-dd strings compare correctly lexicographically.
    return aIn < bOut && bIn < aOut;
}

// Checks a property is free for the requested window.
isolated function isFree(string propertyId, string checkIn, string checkOut)
        returns boolean {
    lock {
        DateRange[]? existing = reservedDates[propertyId];
        if existing is () {
            return true;
        }
        foreach DateRange r in existing {
            if overlaps(checkIn, checkOut, r.checkIn, r.checkOut) {
                return false;
            }
        }
        return true;
    }
}

// Seed a little data so the client is demonstrable immediately.
function init() {
    lock {
        userStore["H001"] = {
            user_id: "H001",
            name: "Maria Shikongo",
            email: "maria@example.na",
            role: HOST,
            phone: "081 000 0001"
        };
        userStore["G001"] = {
            user_id: "G001",
            name: "Peter Amutenya",
            email: "peter@example.na",
            role: GUEST,
            phone: "081 000 0002"
        };
    }
    lock {
        propertyStore["P001"] = {
            property_id: "P001",
            host_id: "H001",
            name: "Dune View Guesthouse",
            location: "Swakopmund",
            property_type: "GUESTHOUSE",
            price_per_night: 850.00,
            status: AVAILABLE,
            description: "Two-bedroom guesthouse a short walk from the beach.",
            max_guests: 4
        };
        propertyStore["P002"] = {
            property_id: "P002",
            host_id: "H001",
            name: "Etosha Safari Lodge Room",
            location: "Otjiwarongo",
            property_type: "LODGE",
            price_per_night: 1200.00,
            status: AVAILABLE,
            description: "Ensuite lodge room with waterhole access.",
            max_guests: 2
        };
    }
    log:printInfo("Rental Accommodation System started on port 9090");
}

// ---------------------------------------------------------------------------
// gRPC service
// ---------------------------------------------------------------------------

@grpc:ServiceDescriptor {
    descriptor: ROOT_DESCRIPTOR_RENTAL,
    descMap: getDescriptorMapRental()
}
service "RentalService" on new grpc:Listener(9090) {

    // -----------------------------------------------------------------------
    // add_property — Simple RPC
    // -----------------------------------------------------------------------
    remote function add_property(AddPropertyRequest request)
            returns AddPropertyResponse|error {

        if request.name.trim().length() == 0 {
            return {
                success: false,
                property_id: "",
                message: "Property name must not be empty."
            };
        }
        if request.price_per_night <= 0.0 {
            return {
                success: false,
                property_id: "",
                message: "Price per night must be greater than zero."
            };
        }

        // Confirm the host exists and actually holds the HOST role.
        lock {
            User? host = userStore[request.host_id];
            if host is () {
                return {
                    success: false,
                    property_id: "",
                    message: string `No user registered with id '${request.host_id}'.`
                };
            }
            if host.role != HOST {
                return {
                    success: false,
                    property_id: "",
                    message: "Only users with the HOST role may register a listing."
                };
            }
        }

        string newId = "P-" + uuid:createType1AsString().substring(0, 8);
        Property newProperty = {
            property_id: newId,
            host_id: request.host_id,
            name: request.name,
            location: request.location,
            property_type: request.property_type,
            price_per_night: request.price_per_night,
            status: request.status,
            description: request.description,
            max_guests: request.max_guests
        };

        lock {
            propertyStore[newId] = newProperty.cloneReadOnly();
        }

        log:printInfo("Property registered", id = newId, host = request.host_id);
        return {
            success: true,
            property_id: newId,
            message: string `Property '${request.name}' registered successfully.`
        };
    }

    // -----------------------------------------------------------------------
    // create_users — Client-side streaming RPC
    // -----------------------------------------------------------------------
    remote function create_users(stream<CreateUserRequest, grpc:Error?> clientStream)
            returns CreateUsersSummary|error {

        int created = 0;
        int rejected = 0;
        string[] errors = [];

        // Consume the whole client stream, then reply once.
        check from CreateUserRequest req in clientStream
            do {
                if req.user_id.trim().length() == 0 {
                    rejected += 1;
                    errors.push("A user was rejected: user_id must not be empty.");
                } else if req.email.trim().length() == 0 || !req.email.includes("@") {
                    rejected += 1;
                    errors.push(string `User '${req.user_id}' rejected: invalid email address.`);
                } else {
                    boolean duplicate = false;
                    lock {
                        duplicate = userStore.hasKey(req.user_id);
                    }
                    if duplicate {
                        rejected += 1;
                        errors.push(string `User '${req.user_id}' rejected: id already registered.`);
                    } else {
                        User newUser = {
                            user_id: req.user_id,
                            name: req.name,
                            email: req.email,
                            role: req.role,
                            phone: req.phone
                        };
                        lock {
                            userStore[req.user_id] = newUser.cloneReadOnly();
                        }
                        created += 1;
                    }
                }
            };

        log:printInfo("User batch processed", created = created, rejected = rejected);
        return {
            success: rejected == 0,
            users_created: created,
            users_rejected: rejected,
            errors: errors,
            message: string `Registered ${created} user(s); rejected ${rejected}.`
        };
    }

    // -----------------------------------------------------------------------
    // update_property — Simple RPC
    // -----------------------------------------------------------------------
    remote function update_property(UpdatePropertyRequest request)
            returns UpdatePropertyResponse|error {

        lock {
            Property? existing = propertyStore[request.property_id];
            if existing is () {
                return {
                    success: false,
                    property: {},
                    message: string `No property found with id '${request.property_id}'.`
                };
            }

            Property updated = existing.clone();

            // Only overwrite fields the caller actually supplied.
            if request.name.trim().length() > 0 {
                updated.name = request.name;
            }
            if request.location.trim().length() > 0 {
                updated.location = request.location;
            }
            if request.property_type.trim().length() > 0 {
                updated.property_type = request.property_type;
            }
            if request.price_per_night > 0.0 {
                updated.price_per_night = request.price_per_night;
            }
            if request.description.trim().length() > 0 {
                updated.description = request.description;
            }
            if request.max_guests > 0 {
                updated.max_guests = request.max_guests;
            }
            updated.status = request.status;

            propertyStore[request.property_id] = updated.cloneReadOnly();

            return {
                success: true,
                property: updated.cloneReadOnly(),
                message: string `Property '${request.property_id}' updated.`
            };
        }
    }

    // -----------------------------------------------------------------------
    // remove_property — Simple RPC
    // Returns the new full list of available properties in the Host's region.
    // -----------------------------------------------------------------------
    remote function remove_property(RemovePropertyRequest request)
            returns RemovePropertyResponse|error {

        lock {
            Property? existing = propertyStore[request.property_id];
            if existing is () {
                return {
                    success: false,
                    message: string `No property found with id '${request.property_id}'.`,
                    remaining_properties: []
                };
            }
            if existing.host_id != request.host_id {
                return {
                    success: false,
                    message: "A property can only be removed by the Host who owns it.",
                    remaining_properties: []
                };
            }

            string region = existing.location;
            _ = propertyStore.remove(request.property_id);

            Property[] remaining = from Property p in propertyStore
                where p.location == region && p.status == AVAILABLE
                select p;

            return {
                success: true,
                message: string `Property '${request.property_id}' removed.`,
                remaining_properties: remaining.cloneReadOnly()
            };
        }
    }

    // -----------------------------------------------------------------------
    // list_available_properties — Server-side streaming RPC
    // -----------------------------------------------------------------------
    remote function list_available_properties(ListAvailableRequest request,
            PropertyCaller caller) returns error? {

        Property[] snapshot;
        lock {
            snapshot = from Property p in propertyStore
                where p.status == AVAILABLE
                select p;
            snapshot = snapshot.cloneReadOnly();
        }

        boolean filterLocation = request.location.trim().length() > 0;
        boolean filterMin = request.min_price > 0.0;
        boolean filterMax = request.max_price > 0.0;

        int sent = 0;
        foreach Property p in snapshot {
            if filterLocation && !p.location.equalsIgnoreCaseAscii(request.location) {
                continue;
            }
            if filterMin && p.price_per_night < request.min_price {
                continue;
            }
            if filterMax && p.price_per_night > request.max_price {
                continue;
            }

            // Stream each matching property back one at a time.
            check caller->sendProperty(p);
            sent += 1;
        }

        log:printInfo("Streamed property list", count = sent);
        check caller->complete();
        return;
    }

    // -----------------------------------------------------------------------
    // search_property — Simple RPC
    // -----------------------------------------------------------------------
    remote function search_property(SearchPropertyRequest request)
            returns SearchPropertyResponse|error {

        lock {
            Property? found = propertyStore[request.property_id];
            if found is () {
                return {
                    found: false,
                    property: {},
                    message: "Not Available"
                };
            }
            if found.status != AVAILABLE {
                return {
                    found: false,
                    property: found.cloneReadOnly(),
                    message: "Not Available"
                };
            }
            return {
                found: true,
                property: found.cloneReadOnly(),
                message: "Property found."
            };
        }
    }

    // -----------------------------------------------------------------------
    // book_property — Simple RPC
    // Validates dates and adds the request to a temporary booking cart.
    // -----------------------------------------------------------------------
    remote function book_property(BookPropertyRequest request)
            returns BookPropertyResponse|error {

        // Guest must exist.
        lock {
            if !userStore.hasKey(request.guest_id) {
                return {
                    success: false,
                    cart_id: "",
                    message: string `No user registered with id '${request.guest_id}'.`,
                    nights: 0,
                    estimated_total: 0.0
                };
            }
        }

        Property property;
        lock {
            Property? found = propertyStore[request.property_id];
            if found is () {
                return {
                    success: false,
                    cart_id: "",
                    message: string `No property found with id '${request.property_id}'.`,
                    nights: 0,
                    estimated_total: 0.0
                };
            }
            if found.status != AVAILABLE {
                return {
                    success: false,
                    cart_id: "",
                    message: "That property is not currently available for booking.",
                    nights: 0,
                    estimated_total: 0.0
                };
            }
            property = found.cloneReadOnly();
        }

        // Basic date validation: end date must be after start date.
        int|error nights = nightsBetween(request.check_in, request.check_out);
        if nights is error {
            return {
                success: false,
                cart_id: "",
                message: nights.message(),
                nights: 0,
                estimated_total: 0.0
            };
        }

        // Reject a window that already clashes with a confirmed booking.
        if !isFree(request.property_id, request.check_in, request.check_out) {
            return {
                success: false,
                cart_id: "",
                message: "Those dates overlap an existing confirmed booking.",
                nights: nights,
                estimated_total: 0.0
            };
        }

        string cartId = "CART-" + uuid:createType1AsString().substring(0, 8);
        double estimate = property.price_per_night * <double>nights;

        Booking pending = {
            booking_id: cartId,
            property_id: request.property_id,
            guest_id: request.guest_id,
            check_in: request.check_in,
            check_out: request.check_out,
            nights: nights,
            total_cost: estimate,
            status: "PENDING"
        };

        lock {
            cartStore[cartId] = pending.cloneReadOnly();
        }

        return {
            success: true,
            cart_id: cartId,
            message: string `Added to cart. ${nights} night(s) at ${property.price_per_night} per night.`,
            nights: nights,
            estimated_total: estimate
        };
    }

    // -----------------------------------------------------------------------
    // confirm_booking — Simple RPC
    // Re-verifies availability, calculates the final cost, returns a
    // confirmation and clears the temporary request.
    // -----------------------------------------------------------------------
    remote function confirm_booking(ConfirmBookingRequest request)
            returns ConfirmBookingResponse|error {

        Booking pending;
        lock {
            Booking? cart = cartStore[request.cart_id];
            if cart is () {
                return {
                    success: false,
                    booking: {},
                    message: string `No pending request found for cart '${request.cart_id}'.`
                };
            }
            if cart.guest_id != request.guest_id {
                return {
                    success: false,
                    booking: {},
                    message: "That cart belongs to a different guest."
                };
            }
            pending = cart.cloneReadOnly();
        }

        // Step 1: re-verify the property is still available for those dates.
        if !isFree(pending.property_id, pending.check_in, pending.check_out) {
            lock {
                _ = cartStore.remove(request.cart_id);
            }
            return {
                success: false,
                booking: {},
                message: "Those dates were taken while the request was pending. Cart cleared."
            };
        }

        // Step 2: recalculate the total from the current price.
        double pricePerNight;
        lock {
            Property? p = propertyStore[pending.property_id];
            if p is () {
                _ = cartStore.remove(request.cart_id);
                return {
                    success: false,
                    booking: {},
                    message: "The property was removed while the request was pending."
                };
            }
            pricePerNight = p.price_per_night;
        }

        double finalCost = pricePerNight * <double>pending.nights;
        string bookingId = "BK-" + uuid:createType1AsString().substring(0, 8);

        Booking confirmed = {
            booking_id: bookingId,
            property_id: pending.property_id,
            guest_id: pending.guest_id,
            check_in: pending.check_in,
            check_out: pending.check_out,
            nights: pending.nights,
            total_cost: finalCost,
            status: "CONFIRMED"
        };

        // Step 3: persist, block the dates, and clear the cart.
        lock {
            bookingStore[bookingId] = confirmed.cloneReadOnly();

            DateRange[] ranges = reservedDates[pending.property_id] ?: [];
            ranges.push({
                checkIn: pending.check_in,
                checkOut: pending.check_out
            });
            reservedDates[pending.property_id] = ranges.cloneReadOnly();

            _ = cartStore.remove(request.cart_id);
        }

        log:printInfo("Booking confirmed", id = bookingId, total = finalCost);
        return {
            success: true,
            booking: confirmed.cloneReadOnly(),
            message: string `Booking confirmed. ${pending.nights} night(s), total ${finalCost}.`
        };
    }
}
